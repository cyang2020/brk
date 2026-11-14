#!/usr/bin/env python3
"""Validate release authority and render GitHub notes, Help history, and Sparkle feeds."""
import argparse
import base64
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import format_datetime
import html
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def version_key(version):
    if not SEMVER.fullmatch(version):
        raise ValueError("VERSION must be a stable SemVer such as 0.0.1")
    return tuple(map(int, version.split(".")))


def build_number(value):
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise ValueError("build must be a positive integer (GITHUB_RUN_NUMBER in CI)")
    return value


def repository_name(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("repository must be owner/name")
    return value


@dataclass(frozen=True)
class Release:
    version: str
    notes: str

    @classmethod
    def load(cls, root, version=None):
        version = version or (root / "VERSION").read_text().strip()
        version_key(version)
        notes = (root / "releases" / (version + ".md")).read_text().strip()
        lines = notes.splitlines()
        if not lines or lines[0] != "# Brk " + version:
            raise ValueError("release notes must start with '# Brk " + version + "'")
        if not any(line.strip().lstrip("-* ") and not line.startswith("#") for line in lines[1:]):
            raise ValueError("release notes must describe user-visible changes")
        return cls(version, notes)

    def markdown(self, signed, build, commit):
        installation = ("Signed with a Developer ID and notarized by Apple." if signed else
                        "This test build is signed ad hoc. It is not offered by the stable updater.")
        return (self.notes + "\n\n## Install\n\n"
                "For macOS 14 or later. Download `Brk-arm64.dmg` for Apple silicon or "
                "`Brk-x86_64.dmg` for Intel. Open the disk image and drag Brk into Applications.\n\n"
                + installation + "\n\nBuild " + build_number(build) + " from `" + commit + "`.\n")


def inline(text):
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)


def notes_html(release):
    output, paragraph, listing = [], [], False
    for line in release.notes.splitlines() + [""]:
        if line and not line.startswith(("#", "- ")):
            paragraph.append(line)
            continue
        if paragraph:
            output.append("<p>" + inline(" ".join(paragraph)) + "</p>")
            paragraph = []
        if listing and not line.startswith("- "):
            output.append("</ul>")
            listing = False
        if line.startswith("- "):
            if not listing:
                output.append("<ul>")
                listing = True
            output.append("<li>" + inline(line[2:]) + "</li>")
        elif line.startswith("#"):
            heading, _, text = line.partition(" ")
            level = min(len(heading) + 1, 6)
            output.append("<h%d>%s</h%d>" % (level, inline(text), level))
    return "\n".join(output)


def history_html(root, current, history):
    releases = [current]
    if history:
        releases = [Release.load(root, path.stem) for path in (root / "releases").glob("*.md")
                    if version_key(path.stem) <= version_key(current.version)]
        releases.sort(key=lambda release: version_key(release.version), reverse=True)
    body = "\n".join('<section id="v%s">%s</section>' % (release.version, notes_html(release))
                     for release in releases)
    return ("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width\">"
            "<title>Brk release notes</title><style>"
            ":root{color-scheme:light dark}body{font:15px/1.55 -apple-system,sans-serif;"
            "max-width:760px;margin:40px auto;padding:0 24px}h1{font-size:28px}"
            "h2{margin-top:32px}h3{font-size:17px}li{margin:8px 0}"
            "code{font-size:13px}section{margin-bottom:40px}"
            "</style></head><body><h1>Brk release notes</h1>\n" + body + "\n</body></html>\n")


def appcast(release, repository, arch, build, archive, signature, date):
    repository_name(repository)
    build_number(build)
    if date.tzinfo is None:
        raise ValueError("appcast date must include a timezone")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Sparkle Ed25519 signature must contain 64 bytes")
    if archive.name != "Brk-" + arch + ".dmg" or archive.stat().st_size == 0:
        raise ValueError("archive must be a nonempty Brk-<arch>.dmg")
    base = "https://github.com/" + repository + "/releases/download/v" + release.version + "/"
    feed = ET.Element("rss", version="2.0")
    channel = ET.SubElement(feed, "channel")
    ET.SubElement(channel, "title").text = "Brk " + arch + " updates"
    ET.SubElement(channel, "link").text = "https://github.com/" + repository + "/releases"
    ET.SubElement(channel, "description").text = "Signed Brk releases for macOS"
    ET.SubElement(channel, "language").text = "en"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "Brk " + release.version
    ET.SubElement(item, "pubDate").text = format_datetime(date)
    ET.SubElement(item, "link").text = "https://github.com/" + repository + "/releases/tag/v" + release.version
    for name, text in (("version", build), ("shortVersionString", release.version),
                       ("minimumSystemVersion", "14.0.0"), ("releaseNotesLink", base + "release-notes.html")):
        ET.SubElement(item, "{" + SPARKLE + "}" + name).text = text
    if arch == "arm64":
        ET.SubElement(item, "{" + SPARKLE + "}hardwareRequirements").text = "arm64"
    ET.SubElement(item, "enclosure", {"url": base + archive.name, "length": str(archive.stat().st_size),
                                     "type": "application/octet-stream", "{" + SPARKLE + "}edSignature": signature})
    ET.indent(feed)
    return ET.tostring(feed, encoding="unicode", xml_declaration=True) + "\n"


def github_json(repository, endpoint):
    result = subprocess.run(["gh", "api", "repos/" + repository_name(repository) + "/" + endpoint],
                            capture_output=True, text=True)
    if result.returncode:
        if "HTTP 404" in result.stderr:
            return None
        raise ValueError("GitHub preflight failed for " + endpoint + "; check API access")
    return json.loads(result.stdout)


def published_release(repository, version, commit):
    tag = github_json(repository, "git/ref/tags/v" + version)
    release = github_json(repository, "releases/tags/v" + version)
    if tag:
        target = tag["object"]
        while target["type"] == "tag":
            target = github_json(repository, "git/tags/" + target["sha"])["object"]
        if target["type"] != "commit" or target["sha"] != commit:
            raise ValueError("v" + version + " already targets different code; bump VERSION and add release notes")
    elif release:
        raise ValueError("published version has no matching tag; repair its metadata without rebuilding")
    return bool(release and not release["draft"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    commands = parser.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate")
    validate.add_argument("--tag")
    validate.add_argument("--check-published", action="store_true")
    validate.add_argument("--repository")
    validate.add_argument("--commit")
    validate.add_argument("--build")
    commands.add_parser("version")
    markdown = commands.add_parser("markdown")
    markdown.add_argument("--signed", choices=("true", "false"), default="false")
    markdown.add_argument("--build", default="1")
    markdown.add_argument("--commit", default="local")
    page = commands.add_parser("html")
    page.add_argument("--history", action="store_true")
    feed = commands.add_parser("appcast")
    feed.add_argument("--repository", required=True)
    feed.add_argument("--arch", choices=("arm64", "x86_64"), required=True)
    feed.add_argument("--build", required=True)
    feed.add_argument("--archive", type=Path, required=True)
    feed.add_argument("--signature-file", type=Path, required=True)
    feed.add_argument("--date", type=datetime.fromisoformat, default=datetime.now(timezone.utc))
    args = parser.parse_args()
    try:
        release = Release.load(args.root)
        if args.command == "validate":
            if args.build is not None:
                build_number(args.build)
            if args.tag and args.tag != "v" + release.version:
                raise ValueError("tag must agree with VERSION (v" + release.version + ")")
            published = False
            if args.check_published:
                if not args.repository or not args.commit:
                    raise ValueError("publication validation needs --repository and --commit")
                published = published_release(args.repository, release.version, args.commit)
            print(json.dumps({"version": release.version, "published": published}))
        elif args.command == "version":
            print(release.version)
        elif args.command == "markdown":
            print(release.markdown(args.signed == "true", args.build, args.commit), end="")
        elif args.command == "html":
            print(history_html(args.root, release, args.history), end="")
        elif args.command == "appcast":
            print(appcast(release, args.repository, args.arch, args.build, args.archive,
                          args.signature_file.read_text().strip(), args.date), end="")
    except (ValueError, OSError) as error:
        parser.exit(1, "release: " + str(error) + "\n")


if __name__ == "__main__":
    main()
