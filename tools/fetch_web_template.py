"""Fetch only Godot's official single-threaded web export template.

The official .tpz contains every platform (over 1 GB). HTTP byte ranges let us
verify and extract the web member without downloading unrelated platforms.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import struct
import tempfile
import urllib.request
import zipfile
from pathlib import Path

VERSION = "4.7.2"
URL = (
    "https://godot-releases.nbg1.your-objectstorage.com/"
    f"{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
)
MEMBER = "templates/web_nothreads_release.zip"


def request_range(start: int, end: int) -> bytes:
    request = urllib.request.Request(
        URL, headers={"Range": f"bytes={start}-{end}", "User-Agent": "EVW-web-build"}
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status != 206:
            raise RuntimeError("Official download server did not honor byte ranges")
        content = response.read()
    if len(content) != end - start + 1:
        raise RuntimeError("Incomplete Godot template download")
    return content


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    request = urllib.request.Request(URL, method="HEAD")
    with urllib.request.urlopen(request, timeout=30) as response:
        size = int(response.headers["Content-Length"])
    with tempfile.TemporaryFile() as archive:
        archive.truncate(size)  # Sparse file; only the requested bytes use disk space.
        tail_start = max(0, size - 65536)
        archive.seek(tail_start)
        archive.write(request_range(tail_start, size - 1))
        with zipfile.ZipFile(archive) as source:
            entry = source.getinfo(MEMBER)
            archive.seek(entry.header_offset)
            archive.write(request_range(entry.header_offset, entry.header_offset + 29))
            archive.seek(entry.header_offset)
            header = archive.read(30)
            fields = struct.unpack("<IHHHHHIIIHH", header)
            if fields[0] != 0x04034B50:
                raise RuntimeError("Invalid Godot export template archive")
            data_start = entry.header_offset + 30 + fields[9] + fields[10]
            archive.seek(entry.header_offset + 30)
            archive.write(request_range(entry.header_offset + 30, data_start - 1))
            archive.seek(data_start)
            archive.write(request_range(data_start, data_start + entry.compress_size - 1))
            # ZipFile verifies the embedded member's CRC before returning it.
            content = source.read(entry)
    with zipfile.ZipFile(io.BytesIO(content)) as template:
        if template.testzip() is not None:
            raise RuntimeError("Corrupt web export template")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(content)
    print(f"{args.output}: {len(content)} bytes, sha256={hashlib.sha256(content).hexdigest()}")


if __name__ == "__main__":
    main()
