#!/usr/bin/env python3
"""Write florilegium.zip, the package as one folder, for CTAN and the GitHub release.

    make zip RUN=tools/in-docker          (builds florilegium-doc.pdf first; -> build/florilegium.zip)
    python3 tools/zip.py build/florilegium.zip

The folder holds what FILES below lists: the package (florilegium.sty, every florilegium*.lua,
the TikZ library), the manual (florilegium-doc.pdf and its sources), the sources of the four
documents and of the TikZ specimen sheet, README.md and LICENSE. The same files give the same
bytes: entries sorted, every one dated by SOURCE_DATE_EPOCH (make passes the last commit's time;
the zip holds the start of the day before it), mode 0644, deflated. In README.md and docs/*.md,
a relative link to a file the zip does not hold is pointed at that file in the repository, at
the release's tag (images at their raw bytes), so the links work wherever the folder is read.

Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
"""
import glob
import os
import posixpath
import re
import sys
import time
import zipfile

REPO = "https://github.com/kevinraymond/florilegium"
RAW = "https://raw.githubusercontent.com/kevinraymond/florilegium"
TOP = "florilegium"

FILES = [
    # the package
    "florilegium.sty",
    "florilegium*.lua",
    "tikzlibraryflorilegium.code.tex",
    "tikzlibraryflorilegium.tables.code.tex",
    # the manual, which texdoc florilegium opens, and what it is typeset from
    "florilegium-doc.pdf",
    "florilegium-doc.tex",
    "docs/*.md",
    "docs/manual.lua",
    # the documents (their PDFs are attached to each release) and the TikZ specimen sheet
    "florilegium.tex",
    "florilegium-grow.tex",
    "showcase.tex",
    "spread.tex",
    "text-methods.tex",
    "text-growth.tex",
    "text-sharing.tex",
    "specimen-tikz.tex",
    "README.md",
    "LICENSE",
]

IMAGE = re.compile(r"\.(png|jpe?g|gif|svg)$", re.I)
LINK = re.compile(r'(\]\(|src=")([^)"\s]+)')


def release():
    with open("florilegium.sty", encoding="utf-8") as f:
        m = re.search(r"\\ProvidesPackage\{florilegium\}\[[0-9/]+ v([0-9.]+)", f.read())
    if not m:
        sys.exit("zip.py: florilegium.sty has no version in \\ProvidesPackage")
    return m.group(1)


def relink(path, text, held, tag):
    """Point relative links to files outside the zip at the repository, at the tag."""
    base = posixpath.dirname(path)

    def swap(m):
        url = m.group(2)
        if re.match(r"[a-z][a-z0-9+.-]*:", url, re.I) or url.startswith("#"):
            return m.group(0)
        target, _, anchor = url.partition("#")
        full = posixpath.normpath(posixpath.join(base, target))
        if full in held:
            return m.group(0)
        if IMAGE.search(full):
            new = f"{RAW}/{tag}/{full}"
        else:
            new = f"{REPO}/blob/{tag}/{full}" + (f"#{anchor}" if anchor else "")
        return m.group(1) + new

    return LINK.sub(swap, text)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "build/florilegium.zip"
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if not epoch:
        sys.exit("zip.py: set SOURCE_DATE_EPOCH (make zip sets it to the last commit's time)")
    # A zip's dates carry no time zone, so an unzip reads them as local time; the start of the
    # day before the commit, in UTC, is in the past in every zone (pkgcheck's W0011 otherwise)
    day = 86400
    stamp = time.gmtime(max(int(epoch) // day * day - day, 315532800))[:6]   # not before 1980
    tag = "v" + release()

    names = []
    for pattern in FILES:
        found = sorted(glob.glob(pattern))
        if not found:
            sys.exit(f"zip.py: nothing matches {pattern}" +
                     (" (make florilegium-doc.pdf first)" if pattern.endswith(".pdf") else ""))
        names += found
    names = sorted(set(names))
    held = set(names)

    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with zipfile.ZipFile(out, "w") as z:
        for name in names:
            with open(name, "rb") as f:
                data = f.read()
            if name.endswith(".md"):
                data = relink(name, data.decode("utf-8"), held, tag).encode("utf-8")
            info = zipfile.ZipInfo(f"{TOP}/{name}", date_time=stamp)
            info.external_attr = 0o100644 << 16
            info.create_system = 3          # unix, so the mode is read
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data, compresslevel=9)
    print(f"{out}: {len(names)} files, {os.path.getsize(out)} bytes, links at {tag}")


if __name__ == "__main__":
    main()
