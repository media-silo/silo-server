#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 the media-silo project authors
"""Fail when a specification pins a requirement to something that does not exist.

Every requirement under `openspec/specs/` ends with a `Pinned by:` paragraph naming the test,
fixture or CI step that measures it. A spec is only as good as those pins: a renamed test or a moved
fixture leaves the requirement claiming a measurement nobody takes, and nothing else notices.

So this checks, for every `Pinned by:` paragraph, that each backticked repository path exists (a
directory, a file, or a glob that matches something), and that each backticked identifier in the
parentheses after a path occurs in that file. The paragraph is read whole — from `Pinned by:` to the
next blank line — because a pin here often wraps, and a name on its second line is as much a claim
as one on the first. URLs into other repositories are not checked here.

`Pinned by: nothing yet.` is a deliberate marker and passes. The count is printed so a growing number
of unpinned requirements is visible in the job log. The same gate runs in SmdKit and the wire
repositories; the paragraph reading is this repository's addition.
"""

import glob
import pathlib
import re
import sys

root = pathlib.Path.cwd()
specs = sorted(root.glob("openspec/specs/*/spec.md"))

token = re.compile(r"`([^`]+)`")
name_list = r"`[^`\s()]+`(?:\s*,\s*`[^`\s()]+`)*"
pin = re.compile(r"`([^`]+)`(?:\s*\((" + name_list + r")\))?")

failures = []
pinned = 0
unpinned = 0


def looks_like_path(text):
    return "/" in text and not text.startswith(("http://", "https://")) and " " not in text


def resolve(text):
    path = root / text.rstrip("/")
    if path.exists():
        return [path]
    return [pathlib.Path(p) for p in glob.glob(str(root / text), recursive=True)]


def paragraphs(lines):
    """Each `Pinned by:` paragraph, joined onto one line, with the line number it starts on."""
    number = 0
    while number < len(lines):
        if lines[number].startswith("Pinned by:"):
            start = number
            joined = [lines[number]]
            number += 1
            while number < len(lines) and lines[number].strip() and not lines[number].startswith("#"):
                joined.append(lines[number].strip())
                number += 1
            yield start + 1, " ".join(joined)
        else:
            number += 1


for spec in specs:
    relative = spec.relative_to(root)
    for number, paragraph in paragraphs(spec.read_text().splitlines()):
        if "nothing yet" in paragraph:
            unpinned += 1
        body = paragraph[len("Pinned by:"):]
        if token.search(body):
            pinned += 1
        # A path is a backticked token containing a slash. When it is followed directly by a
        # parenthesised list made only of backticked names (test functions, fixture names, CI job
        # ids), each name must occur in that file. A parenthetical that is prose ("which measures
        # that…") is not a name list and is skipped.
        for match in pin.finditer(body):
            text, names = match.group(1), match.group(2)
            if not looks_like_path(text):
                continue
            found = resolve(text)
            if not found:
                failures.append(f"{relative}:{number}: no such path `{text}`")
                continue
            if not names:
                continue
            files = [p for p in found if p.is_file()]
            for name in token.findall(names):
                if looks_like_path(name) and re.search(r"\.[A-Za-z]+$", name):
                    # A file named alongside the first, not a name inside it.
                    if not resolve(name):
                        failures.append(f"{relative}:{number}: no such path `{name}`")
                    continue
                if "/" not in name:
                    name = name.split(".")[-1]
                if files and not any(name in p.read_text(errors="ignore") for p in files):
                    shown = files[0].relative_to(root)
                    failures.append(f"{relative}:{number}: `{name}` does not occur in {shown}")

for failure in failures:
    print(failure)

print(
    f"\n{len(specs)} spec(s), {pinned} pinned requirement(s), "
    f"{unpinned} marked 'nothing yet', {len(failures)} broken pin(s)."
)
sys.exit(1 if failures else 0)
