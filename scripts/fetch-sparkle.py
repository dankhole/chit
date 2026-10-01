#!/usr/bin/env python3
"""Fetch the pinned official Sparkle distribution into build/release only."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile


REPO = Path(__file__).resolve().parent.parent
DEPENDENCIES = REPO / "build" / "release" / "dependencies"


def safe_directory(path):
    if path.resolve() != path:
        raise ValueError(f"Release output must not use symbolic links: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path


def fetch(archive=None):
    lock = json.loads((REPO / "config" / "sparkle.json").read_text())
    version, digest = lock["version"], lock["sha256"]
    expected_url = f"https://github.com/sparkle-project/Sparkle/releases/download/{version}/Sparkle-{version}.tar.xz"
    if lock["url"] != expected_url or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise ValueError("Invalid Sparkle dependency lock")
    safe_directory(DEPENDENCIES)
    cached = DEPENDENCIES / f"Sparkle-{version}.tar.xz"
    if cached.is_symlink():
        raise ValueError("Sparkle archive cache must not use a symbolic link")
    source = Path(archive).expanduser().resolve() if archive else cached
    if not source.is_file():
        if archive:
            raise ValueError("Supplied Sparkle archive is missing")
        with tempfile.TemporaryDirectory(prefix="sparkle-download-", dir=DEPENDENCIES) as temporary:
            download = Path(temporary) / "archive.tar.xz"
            subprocess.run(["/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
                            "--proto", "=https", "--proto-redir", "=https", "--retry", "3",
                            "--output", str(download), lock["url"]], check=True)
            if hashlib.sha256(download.read_bytes()).hexdigest() != digest:
                raise ValueError("Downloaded Sparkle archive checksum does not match the lock")
            download.replace(cached)
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise ValueError("Sparkle archive checksum does not match the lock")
    destination = DEPENDENCIES / "sparkle"
    if destination.is_symlink():
        raise ValueError("Sparkle dependency directory must not use a symbolic link")
    # Re-extract verified bytes so stale or locally modified framework files aren't reused.
    with tempfile.TemporaryDirectory(prefix="sparkle-extract-", dir=DEPENDENCIES) as temporary:
        staging = Path(temporary) / "sparkle"
        staging.mkdir()
        with tarfile.open(source) as archive_file:
            members = []
            for member in archive_file.getmembers():
                path = PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Unsafe path in Sparkle archive")
                if not path.parts or path.parts[0] not in ("Sparkle.framework", "bin", "LICENSE"):
                    continue
                if not (member.isfile() or member.isdir() or member.issym()):
                    raise ValueError("Unsupported entry in Sparkle archive")
                if member.issym():
                    target = PurePosixPath(member.linkname)
                    if target.is_absolute() or ".." in target.parts:
                        raise ValueError("Unsafe symbolic link in Sparkle archive")
                members.append(member)
            archive_file.extractall(staging, members=members)
        required = ["Sparkle.framework/Versions/B/Sparkle", "bin/sign_update", "bin/generate_appcast", "LICENSE"]
        if not all((staging / name).is_file() for name in required):
            raise ValueError("Pinned Sparkle archive is missing distribution components")
        if destination.exists():
            shutil.rmtree(destination)
        staging.replace(destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", help="Use an already downloaded archive; the pinned checksum is still required")
    options = parser.parse_args()
    try:
        print(fetch(options.archive))
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Sparkle dependency: {error}\n")


if __name__ == "__main__":
    main()
