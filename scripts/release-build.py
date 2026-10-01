#!/usr/bin/env python3
"""Build an optimized universal Chit distribution without touching local/Lab apps."""

import argparse
import base64
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
from urllib.parse import urlsplit

import importlib.util


REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "build" / "release"
ARCHITECTURES = ("arm64", "x86_64")


def run(arguments, **kwargs):
    return subprocess.run([str(argument) for argument in arguments], check=True, **kwargs)


def sources(directory):
    result = sorted((REPO / directory).rglob("*.swift"))
    if not result:
        raise ValueError(f"No Swift sources in {directory}")
    return result


def validate_options(options):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", options.version):
        raise ValueError("Version must be stable numeric MAJOR.MINOR.PATCH")
    url = urlsplit(options.feed_url)
    placeholder_host = url.hostname and any(url.hostname == host or url.hostname.endswith("." + host)
                                            for host in ("example.com", "example.org", "example.net"))
    try:
        address = ipaddress.ip_address(url.hostname or "")
        local_host = not address.is_global
    except ValueError:
        local_host = False
    if (url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment
            or not url.path.endswith("/appcast.xml") or any(c.isspace() for c in options.feed_url)
            or placeholder_host or local_host or url.hostname == "localhost"
            or url.hostname.endswith((".example", ".invalid", ".test", ".localhost"))):
        raise ValueError("Feed must be a real HTTPS appcast.xml URL without credentials or placeholders")
    try:
        key = base64.b64decode(options.public_ed_key, validate=True)
    except ValueError as error:
        raise ValueError("Sparkle public key must be valid base64") from error
    if len(key) != 32 or key == bytes(32) or base64.b64encode(key).decode("ascii") != options.public_ed_key:
        raise ValueError("Sparkle public key must be a nonzero 32-byte Ed25519 public key")
    if options.signing_identity:
        identities = run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
                         text=True, capture_output=True).stdout
        matches = re.findall(r'\b([0-9A-Fa-f]{40}) "(Developer ID Application: [^"\n]+)"', identities)
        if not any(options.signing_identity == name or options.signing_identity.upper() == digest.upper()
                   for digest, name in matches):
            raise ValueError("Signing identity must select a valid Developer ID Application certificate")


def sign(path, options, preserve=False):
    command = ["/usr/bin/codesign", "--force", "--sign", options.signing_identity or "-"]
    if options.signing_identity:
        command += ["--options", "runtime", "--timestamp"]
    else:
        command += ["--timestamp=none"]
    if preserve:
        command += ["--preserve-metadata=identifier,entitlements"]
    run([*command, path])
    run(["/usr/bin/codesign", "--verify", "--strict", path])
    if options.signing_identity:
        details = run(["/usr/bin/codesign", "--display", "--verbose=4", path], text=True, capture_output=True).stderr
        if ("Authority=Developer ID Application:" not in details
                or not re.search(r"flags=.*\bruntime\b", details)
                or not re.search(r"^Timestamp=.+$", details, re.MULTILINE)):
            raise ValueError(f"Missing Developer ID/hardened runtime/timestamp signature: {path}")
        team = re.search(r"^TeamIdentifier=([A-Z0-9]+)$", details, re.MULTILINE)
        if not team:
            raise ValueError(f"Missing signing team: {path}")
        return team.group(1)
    return None


def build(options):
    validate_options(options)
    # Never follow a redirected build/release tree or reuse an incomplete app bundle.
    if OUT.resolve() != OUT:
        raise ValueError("Release output must not use symbolic links")
    OUT.mkdir(parents=True, exist_ok=True)
    receipt = OUT / "build.json"
    if receipt.is_symlink():
        raise ValueError("Release receipt must not use a symbolic link")
    receipt.unlink(missing_ok=True)
    for name in ("work", "Chit.app", "chit", "todo"):
        path = OUT / name
        if path.is_symlink():
            raise ValueError(f"Release output must not use symbolic links: {path}")
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    spec = importlib.util.spec_from_file_location("chit_fetch_sparkle", REPO / "scripts" / "fetch-sparkle.py")
    fetcher = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fetcher)
    dependency = fetcher.fetch(options.sparkle_archive)
    sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True, capture_output=True).stdout.strip()
    app = OUT / "Chit.app"
    for name in ("MacOS", "Resources/bin", "Frameworks"):
        (app / "Contents" / name).mkdir(parents=True, exist_ok=True)
    for architecture in ARCHITECTURES:
        work = OUT / "work" / architecture
        work.mkdir(parents=True)
        target = architecture + "-apple-macosx14.0"
        run(["/bin/bash", "-c", 'source "$1"; build_yaml "$2" "$3" "$4" "$5"',
             "build-yaml", REPO / "scripts" / "build-yaml.sh", REPO, work, sdk, target])
        common = ["-sdk", sdk, "-target", target, "-swift-version", "5", "-O", "-whole-module-optimization",
                  "-module-cache-path", work / "ModuleCache", "-I", REPO / "Sources" / "CChitYAML"]
        run(["xcrun", "swiftc", *common, "-parse-as-library", "-emit-library", "-static", "-emit-module",
             "-module-name", "TodoCore", "-emit-module-path", work / "TodoCore.swiftmodule",
             *sources("Sources/TodoCore"), "-o", work / "libTodoCore.a"])
        links = ["-I", work, "-L", work, "-lTodoCore", "-lChitYAML"]
        run(["xcrun", "swiftc", *common, *links, *sources("Sources/ChitCLI"), "-module-name", "ChitCLI",
             "-o", work / "chit"])
        run(["xcrun", "swiftc", *common, *links, "-D", "CHIT_DISTRIBUTION", "-F", dependency,
             "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
             *sources("Sources/Chit"), "-module-name", "Chit", "-o", work / "Chit"])
    for executable, output in (("Chit", app / "Contents/MacOS/Chit"), ("chit", OUT / "chit")):
        run(["xcrun", "lipo", "-create", *[OUT / "work" / arch / executable for arch in ARCHITECTURES], "-output", output])
        run(["xcrun", "lipo", output, "-verify_arch", *ARCHITECTURES])
    shutil.copy2(OUT / "chit", app / "Contents/Resources/bin/chit")
    shutil.copy2(OUT / "chit", app / "Contents/MacOS/todo")
    framework = app / "Contents/Frameworks/Sparkle.framework"
    shutil.copytree(dependency / "Sparkle.framework", framework, symlinks=True)
    shutil.copy2(REPO / "Vendor/libyaml/LICENSE", app / "Contents/Resources/libyaml-LICENSE")
    shutil.copy2(dependency / "LICENSE", app / "Contents/Resources/Sparkle-LICENSE")
    with (REPO / "Resources/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    info.update(CFBundleExecutable="Chit", CFBundleIdentifier="local.dcole.TotTodo",
                CFBundleShortVersionString=options.version, CFBundleVersion=options.version,
                LSMinimumSystemVersion="14.0", SUFeedURL=options.feed_url,
                SUPublicEDKey=options.public_ed_key)
    with (app / "Contents/Info.plist").open("wb") as output:
        plistlib.dump(info, output)
    nested = [framework / "Versions/B/Autoupdate", framework / "Versions/B/Updater.app",
              framework / "Versions/B/XPCServices/Downloader.xpc", framework / "Versions/B/XPCServices/Installer.xpc",
              framework]
    teams = set()
    for path in nested:
        if not path.exists():
            raise ValueError(f"Pinned Sparkle framework component missing: {path}")
        executable = path
        if path.suffix in (".app", ".xpc"):
            executable = path / "Contents/MacOS" / path.stem
        elif path.suffix == ".framework":
            executable = path / "Versions/B/Sparkle"
        run(["xcrun", "lipo", executable, "-verify_arch", *ARCHITECTURES])
        team = sign(path, options, preserve=True)
        if team:
            teams.add(team)
    for path in (app / "Contents/Resources/bin/chit", app / "Contents/MacOS/todo", app):
        team = sign(path, options)
        if team:
            teams.add(team)
    if options.signing_identity and len(teams) != 1:
        raise ValueError("Embedded components and app must share the same signing team")
    run(["xcrun", "lipo", framework / "Versions/B/Sparkle", "-verify_arch", *ARCHITECTURES])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    # Standalone convenience copies remain identical to the signed bundled CLI.
    shutil.copy2(app / "Contents/Resources/bin/chit", OUT / "chit")
    shutil.copy2(app / "Contents/MacOS/todo", OUT / "todo")
    receipt.write_text(json.dumps({"version": options.version, "architectures": list(ARCHITECTURES),
                                  "signed": bool(options.signing_identity), "notarized": False,
                                  "team": next(iter(teams), None), "feed_url": options.feed_url,
                                  "sparkle_version": json.loads((REPO / "config/sparkle.json").read_text())["version"]}, indent=2) + "\n")
    print(f"Built universal {'Developer ID signed' if options.signing_identity else 'ad-hoc validation-only'} app: {app}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--feed-url", required=True)
    parser.add_argument("--public-ed-key", required=True, help="Public Ed25519 update key (never a private key)")
    signing = parser.add_mutually_exclusive_group(required=True)
    signing.add_argument("--signing-identity", help="Developer ID Application certificate name or SHA1 hash")
    signing.add_argument("--ad-hoc", action="store_true", help="Validation only; cannot produce a publishable build")
    parser.add_argument("--sparkle-archive", help="Use a local official archive after pinned checksum verification")
    options = parser.parse_args()
    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    try:
        build(options)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release build: {error}\n")


if __name__ == "__main__":
    main()
