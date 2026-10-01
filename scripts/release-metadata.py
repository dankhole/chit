#!/usr/bin/env python3
"""Generate Sparkle and Homebrew metadata from the final release archive.

Run after app signing, packaging, and any optional notarization/stapling.
Sparkle's sign_update tool owns
archive signing; this script accepts its public EdDSA signature, never a key.
The appcast intentionally offers one stable, universal, full-archive update.
"""

import argparse
import base64
import binascii
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ATOM_NAMESPACE = "http://www.w3.org/2005/Atom"
CASK_TEMPLATE = Path(__file__).resolve().parent.parent / "distribution/chit.rb.in"
AD_HOC_CAVEATS = """  caveats <<~EOS
    Chit is ad hoc signed and is not notarized by Apple.
    If macOS blocks the first launch and you trust this release, use
    Open Anyway in System Settings > Privacy & Security after trying to open Chit.
  EOS"""
VERSION_PATTERN = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")
REPOSITORY_PATTERN = re.compile(
    r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}"
)
TIMESTAMP_PATTERN = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})"
)


def validate_inputs(version, repository, signature, published_at):
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError("version must be a stable X.Y.Z numeric version without a v prefix")
    if not REPOSITORY_PATTERN.fullmatch(repository) or "--" in repository.split("/")[0]:
        raise ValueError("repository must be a GitHub owner/name, not a URL")
    try:
        decoded = base64.b64decode(signature, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ValueError("signature must be Sparkle's canonical base64 EdDSA signature") from error
    if len(decoded) != 64 or base64.b64encode(decoded).decode("ascii") != signature:
        raise ValueError("signature must be Sparkle's canonical base64 64-byte EdDSA signature")
    if published_at is None:
        return datetime.now(timezone.utc)
    if not TIMESTAMP_PATTERN.fullmatch(published_at):
        raise ValueError("published-at must be an ISO8601 timestamp with a timezone")
    try:
        return datetime.fromisoformat(published_at.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError as error:
        raise ValueError("published-at must be a valid ISO8601 timestamp") from error


def archive_digest(archive, version):
    if archive.name != f"Chit-{version}.zip":
        raise ValueError("archive must be named Chit-X.Y.Z.zip for the supplied version")
    if not archive.is_file():
        raise ValueError("archive must be an existing release ZIP file")
    digest = hashlib.sha256()
    length = 0
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
            length += len(chunk)
    if length == 0:
        raise ValueError("archive must not be empty")
    return digest.hexdigest(), length


def generate(version, archive, signature, repository, output_directory, published_at=None, mode="ad-hoc"):
    """Write appcast.xml and chit.rb, using only validated release values."""
    if mode not in ("ad-hoc", "notarized"):
        raise ValueError("mode must be ad-hoc or notarized")
    published = validate_inputs(version, repository, signature, published_at)
    archive = Path(archive)
    checksum, length = archive_digest(archive, version)
    homepage = f"https://github.com/{repository}"
    release_url = f"{homepage}/releases/tag/v{version}"
    download_url = f"{homepage}/releases/download/v{version}/{archive.name}"
    feed_url = f"{homepage}/releases/latest/download/appcast.xml"

    ET.register_namespace("sparkle", SPARKLE_NAMESPACE)
    ET.register_namespace("atom", ATOM_NAMESPACE)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Chit Updates"
    ET.SubElement(channel, "link").text = f"{homepage}/releases"
    ET.SubElement(channel, "description").text = "Stable Chit updates for macOS 14 and later"
    ET.SubElement(channel, f"{{{ATOM_NAMESPACE}}}link", {
        "href": feed_url, "rel": "self", "type": "application/rss+xml",
    })
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Chit {version}"
    ET.SubElement(item, "link").text = release_url
    ET.SubElement(item, f"{{{SPARKLE_NAMESPACE}}}version").text = version
    ET.SubElement(item, f"{{{SPARKLE_NAMESPACE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE_NAMESPACE}}}minimumSystemVersion").text = "14.0.0"
    ET.SubElement(item, f"{{{SPARKLE_NAMESPACE}}}releaseNotesLink").text = release_url
    ET.SubElement(item, "pubDate").text = format_datetime(published, usegmt=True)
    ET.SubElement(item, "enclosure", {
        "url": download_url,
        f"{{{SPARKLE_NAMESPACE}}}edSignature": signature,
        "length": str(length),
        "type": "application/octet-stream",
        f"{{{SPARKLE_NAMESPACE}}}os": "macos",
    })
    ET.indent(rss, space="  ")
    appcast = ET.tostring(rss, encoding="utf-8", xml_declaration=True).decode("utf-8") + "\n"

    cask = CASK_TEMPLATE.read_text(encoding="utf-8")
    for placeholder, value in {
        "@VERSION@": version,
        "@SHA256@": checksum,
        "@DOWNLOAD_URL@": download_url,
        "@REPOSITORY@": repository,
        "@CAVEATS@": AD_HOC_CAVEATS if mode == "ad-hoc" else "",
    }.items():
        cask = cask.replace(placeholder, value)

    output_directory = Path(output_directory)
    output_directory.mkdir(parents=True, exist_ok=True)
    appcast_path = output_directory / "appcast.xml"
    cask_path = output_directory / "chit.rb"
    appcast_path.write_text(appcast, encoding="utf-8")
    cask_path.write_text(cask, encoding="utf-8")
    return appcast_path, cask_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Stable X.Y.Z version, matching both bundle version keys")
    parser.add_argument("--archive", type=Path, required=True, help="Final Chit-X.Y.Z.zip after app signing and packaging")
    parser.add_argument("--signature", required=True, help="Public base64 signature from Sparkle sign_update")
    parser.add_argument("--repository", required=True, help="Public distribution GitHub repository as owner/name")
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--published-at", help="ISO8601 timestamp with timezone; defaults to current UTC time")
    parser.add_argument("--mode", choices=("ad-hoc", "notarized"), default="ad-hoc",
                        help="App signing mode; ad-hoc adds a first-launch caveat (default)")
    args = parser.parse_args()
    try:
        paths = generate(args.version, args.archive, args.signature, args.repository,
                         args.output_directory, args.published_at, args.mode)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    for path in paths:
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
