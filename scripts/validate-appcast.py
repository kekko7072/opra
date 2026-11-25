#!/usr/bin/env python3
"""Validate the identity and enclosure of a generated Sparkle appcast."""

import argparse
import sys
import urllib.parse
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def fail(message: str) -> None:
    print(f"appcast validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


parser = argparse.ArgumentParser()
parser.add_argument("appcast")
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
parser.add_argument("--tag", required=True)
parser.add_argument("--repository", required=True)
args = parser.parse_args()

try:
    root = ET.parse(args.appcast).getroot()
except (ET.ParseError, OSError) as error:
    fail(str(error))

items = root.findall("./channel/item")
if len(items) != 1:
    fail(f"expected one release item, found {len(items)}")

item = items[0]
enclosure = item.find("enclosure")
if enclosure is None:
    fail("missing enclosure")

version = item.findtext(f"{{{SPARKLE}}}shortVersionString")
build = item.findtext(f"{{{SPARKLE}}}version")
signature = enclosure.get(f"{{{SPARKLE}}}edSignature")
url = enclosure.get("url", "")
expected_prefix = f"https://github.com/{args.repository}/releases/download/{args.tag}/"

if version != args.version:
    fail(f"version is {version!r}, expected {args.version!r}")
if build != args.build:
    fail(f"build is {build!r}, expected {args.build!r}")
if not signature:
    fail("missing EdDSA signature")
if not url.startswith(expected_prefix):
    fail(f"enclosure URL {url!r} does not start with {expected_prefix!r}")
if urllib.parse.urlparse(url).scheme != "https":
    fail("enclosure URL must use HTTPS")

print(f"Validated Sparkle appcast for {args.version} (build {args.build})")
