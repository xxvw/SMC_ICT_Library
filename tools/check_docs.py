#!/usr/bin/env python3
"""Check repository Markdown file links and heading anchors, without network access.

Fenced code, inline code, and HTML comments are examples, not links.
Inline links, images, reference links, and GitHub-style heading anchors are checked.
"""

from __future__ import annotations

import argparse
import html
import re
import subprocess
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
LABEL = r"(?:\\.|[^\]\\\n])*"
INLINE = re.compile(r"!?\[" + LABEL + r"\]\(")
REFERENCE = re.compile(r"!?\[(" + LABEL + r")\]\[(" + LABEL + r")\]")
DEFINITION = re.compile(r"^ {0,3}\[(" + LABEL + r")\]:\s*(.*)$", re.MULTILINE)


def blank(text: str) -> str:
    return re.sub(r"[^\n]", " ", text)


def prose(text: str, *, strip_inline: bool = True) -> str:
    text = re.sub(r"<!--.*?-->", lambda match: blank(match[0]), text, flags=re.DOTALL)
    lines = []
    fence = ""
    for line in text.splitlines(keepends=True):
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if fence:
            if re.match(r"^ {0,3}" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*$", line):
                fence = ""
            lines.append(blank(line))
        elif marker:
            fence = marker[1]
            lines.append(blank(line))
        else:
            lines.append(line)
    result = "".join(lines)
    if strip_inline:
        result = re.sub(r"(`+)(.+?)\1", lambda match: blank(match[0]), result, flags=re.DOTALL)
    return result


def destination(text: str, start: int = 0) -> str:
    """Read an angle-bracket or balanced bare Markdown destination."""
    start += len(text[start:]) - len(text[start:].lstrip())
    if text[start:start + 1] == "<":
        end = text.find(">", start + 1)
        return text[start + 1:end] if end >= 0 else ""
    depth = 0
    end = start
    while end < len(text):
        char = text[end]
        if char == "\\" and end + 1 < len(text):
            end += 2
            continue
        if char.isspace() or (char == ")" and depth == 0):
            break
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        end += 1
    return re.sub(r"\\([\\()\[\]<> ])", r"\1", text[start:end])


def links(text: str) -> list[tuple[int, str]]:
    content = prose(text)
    result = [(match.start(), destination(content, match.end())) for match in INLINE.finditer(content)]
    definitions = {}
    for match in DEFINITION.finditer(content):
        key = " ".join(match[1].split()).casefold()
        value = destination(match[2])
        definitions.setdefault(key, value)
        result.append((match.start(), value))
    for match in REFERENCE.finditer(content):
        key = " ".join((match[2] or match[1]).split()).casefold()
        if key not in definitions:
            result.append((match.start(), "missing-reference:" + key))
    return [(content.count("\n", 0, offset) + 1, value) for offset, value in result]


def anchors(text: str) -> set[str]:
    content = prose(text, strip_inline=False)
    result = set(re.findall(r'<(?:a|[a-z][a-z0-9]*)\b[^>]*\b(?:id|name)=["\']([^"\']+)["\']', content, re.IGNORECASE))
    counts: dict[str, int] = {}
    lines = content.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^ {0,3}#{1,6}\s+(.+?)(?:\s+#+\s*)?$", line)
        title = match[1] if match else ""
        if not title and index and re.match(r"^ {0,3}(?:=+|-+)\s*$", line) and lines[index - 1].strip():
            title = lines[index - 1].strip()
        if not title:
            continue
        title = re.sub(r"!?\[([^\]]+)\]\([^)]*\)", r"\1", title)
        title = html.unescape(re.sub(r"<[^>]+>", "", title)).lower()
        slug = "".join(char for char in title if char in "-_ " or unicodedata.category(char)[0] in "LNM")
        slug = slug.replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        result.add(slug if not count else f"{slug}-{count}")
    return result


def check_file(path: Path, root: Path) -> list[str]:
    failures = []
    for line, target in links(path.read_text(encoding="utf-8")):
        prefix = f"{path.relative_to(root)}:{line}"
        if target.startswith("missing-reference:"):
            failures.append(f"{prefix}: undefined reference {target.partition(':')[2]!r}")
            continue
        try:
            url = urlsplit(html.unescape(target))
        except ValueError:
            failures.append(f"{prefix}: invalid link {target!r}")
            continue
        if url.scheme or url.netloc or not target:
            continue
        local = unquote(url.path)
        candidate = root / local.lstrip("/") if local.startswith("/") else path.parent / local
        if not local:
            candidate = path
        candidate = candidate.resolve()
        if not candidate.is_relative_to(root.resolve()):
            failures.append(f"{prefix}: link escapes the repository: {target}")
        elif not candidate.exists():
            failures.append(f"{prefix}: missing local target: {target}")
        elif url.fragment and candidate.suffix.lower() in {".md", ".markdown"}:
            if unquote(url.fragment) not in anchors(candidate.read_text(encoding="utf-8")):
                failures.append(f"{prefix}: missing heading anchor: {target}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="Markdown paths relative to the repository; defaults to all non-ignored Markdown")
    args = parser.parse_args()
    if args.paths:
        paths = [ROOT / value for value in args.paths]
    else:
        output = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.md", "*.markdown"], cwd=ROOT,
        )
        paths = [ROOT / value for value in output.decode().split("\0") if value]
    failures = []
    for path in sorted(set(paths)):
        if not path.resolve().is_relative_to(ROOT.resolve()) or not path.is_file():
            failures.append(f"{path}: document is missing or outside the repository")
        else:
            failures.extend(check_file(path, ROOT))
    for failure in failures:
        print(failure)
    print(f"Checked {len(set(paths))} Markdown files: {len(failures)} broken local links.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
