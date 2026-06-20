#!/usr/bin/env python3
"""Lightweight static checks for MQL5 source files.

This is not a MetaEditor replacement. It catches repository-local mistakes
that are cheap to verify in CI: unreadable files, unresolved local includes,
obvious delimiter imbalance, and empty source files.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ("Experts", "Indicators", "Scripts", "Include")
SOURCE_SUFFIXES = {".mq5", ".mqh"}
INCLUDE_RE = re.compile(r"^\s*#include\s+([<\"])([^>\"]+)[>\"]", re.MULTILINE)


def iter_sources() -> list[Path]:
    files: list[Path] = []
    for dirname in SOURCE_DIRS:
        base = ROOT / dirname
        if not base.exists():
            continue
        files.extend(
            path
            for path in base.rglob("*")
            if path.is_file() and path.suffix.lower() in SOURCE_SUFFIXES
        )
    return sorted(files)


def strip_comments_and_strings(text: str) -> str:
    result: list[str] = []
    i = 0
    in_line_comment = False
    in_block_comment = False
    in_string: str | None = None

    while i < len(text):
        char = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_line_comment:
            if char == "\n":
                in_line_comment = False
                result.append(char)
            else:
                result.append(" ")
            i += 1
            continue

        if in_block_comment:
            if char == "*" and nxt == "/":
                in_block_comment = False
                result.extend("  ")
                i += 2
            else:
                result.append("\n" if char == "\n" else " ")
                i += 1
            continue

        if in_string:
            if char == "\\" and nxt:
                result.extend("  ")
                i += 2
                continue
            if char == in_string:
                in_string = None
            result.append("\n" if char == "\n" else " ")
            i += 1
            continue

        if char == "/" and nxt == "/":
            in_line_comment = True
            result.extend("  ")
            i += 2
            continue

        if char == "/" and nxt == "*":
            in_block_comment = True
            result.extend("  ")
            i += 2
            continue

        if char in {'"', "'"}:
            in_string = char
            result.append(" ")
            i += 1
            continue

        result.append(char)
        i += 1

    return "".join(result)


def resolve_include(path: Path, delimiter: str, include: str) -> Path | None:
    include_path = Path(include)

    if delimiter == '"':
        candidate = (path.parent / include_path).resolve()
        if candidate.is_file():
            return candidate
        candidate = (ROOT / "Include" / include_path).resolve()
        if candidate.is_file():
            return candidate
        return None

    if include.startswith("SMC/"):
        candidate = (ROOT / "Include" / include_path).resolve()
        if candidate.is_file():
            return candidate
        return None

    return path


def check_delimiters(path: Path, text: str) -> list[str]:
    cleaned = strip_comments_and_strings(text)
    pairs = {"(": ")", "[": "]", "{": "}"}
    closers = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int, int]] = []
    errors: list[str] = []

    line = 1
    column = 0
    for char in cleaned:
        if char == "\n":
            line += 1
            column = 0
            continue

        column += 1
        if char in pairs:
            stack.append((char, line, column))
        elif char in closers:
            if not stack or stack[-1][0] != closers[char]:
                errors.append(f"{path}:{line}:{column}: unmatched '{char}'")
            else:
                stack.pop()

    for char, open_line, open_column in stack:
        errors.append(
            f"{path}:{open_line}:{open_column}: unmatched '{char}'"
        )

    return errors


def check_file(path: Path) -> list[str]:
    rel_path = path.relative_to(ROOT)
    errors: list[str] = []

    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        return [f"{rel_path}:1:1: file is not valid UTF-8: {exc}"]

    if not text.strip():
        errors.append(f"{rel_path}:1:1: file is empty")

    for match in INCLUDE_RE.finditer(text):
        delimiter, include = match.groups()
        if resolve_include(path, delimiter, include) is None:
            line_no = text.count("\n", 0, match.start()) + 1
            errors.append(
                f"{rel_path}:{line_no}:1: unresolved include '{include}'"
            )

    errors.extend(check_delimiters(rel_path, text))
    return errors


def main() -> int:
    files = iter_sources()
    if not files:
        print("No MQL5 source files found.", file=sys.stderr)
        return 1

    errors: list[str] = []
    for path in files:
        errors.extend(check_file(path))

    if errors:
        print("MQL5 static checks failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print(f"MQL5 static checks passed for {len(files)} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
