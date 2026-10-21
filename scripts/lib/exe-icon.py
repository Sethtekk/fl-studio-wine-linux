#!/usr/bin/env python3
"""Extract the largest icon of a Windows .exe (or .ico) as a file.

    python3 exe-icon.py FL64.exe out      -> writes out.png (or out.ico)

Modern icons keep their 256x256 frame as PNG - that one is written directly,
no extra tools needed. Otherwise an .ico with the largest frame is written,
which ImageMagick can convert. Prints the written path; exit 1 if none found.
"""
import struct
import sys


def ico_frames(data):
    """(width, bytes) for every frame of an .ico file."""
    _, _, count = struct.unpack_from("<HHH", data, 0)
    for i in range(count):
        w, h, _, _, _, _, size, off = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
        yield (w or 256), data[off:off + size]


def pe_icons(data):
    """(width, bytes) for every RT_ICON resource of a PE file."""
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        return
    nsec, = struct.unpack_from("<H", data, pe + 6)
    optsize, = struct.unpack_from("<H", data, pe + 20)
    opt = pe + 24
    magic, = struct.unpack_from("<H", data, opt)
    dirs = opt + (112 if magic == 0x20B else 96)
    rsrc_rva, _ = struct.unpack_from("<II", data, dirs + 2 * 8)
    secs = opt + optsize
    sections = [struct.unpack_from("<8sIIII", data, secs + 40 * i) for i in range(nsec)]

    def off(rva):
        for _, vsize, va, rawsize, raw in sections:
            if va <= rva < va + max(vsize, rawsize):
                return raw + rva - va
        raise ValueError("rva outside sections")

    base = off(rsrc_rva)

    def entries(d):
        named, ids = struct.unpack_from("<HH", data, base + d + 12)
        for i in range(named + ids):
            name, target = struct.unpack_from("<II", data, base + d + 16 + 8 * i)
            yield name, target

    for typ, t in entries(0):
        if typ != 3 or not t & 0x80000000:            # RT_ICON
            continue
        for _, n in entries(t & 0x7FFFFFFF):
            for _, leaf in entries(n & 0x7FFFFFFF):
                rva, size = struct.unpack_from("<II", data, base + leaf)
                blob = data[off(rva):off(rva) + size]
                if blob[:8] == b"\x89PNG\r\n\x1a\n":
                    w = struct.unpack_from(">I", blob, 16)[0]
                else:                                   # BITMAPINFOHEADER
                    w = struct.unpack_from("<i", blob, 4)[0]
                yield w, blob


def main():
    src, out = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    frames = list(ico_frames(data) if data[:4] == b"\0\0\1\0" else pe_icons(data))
    if not frames:
        sys.exit(1)
    w, blob = max(frames, key=lambda f: f[0])
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        path = out + ".png"
        open(path, "wb").write(blob)
    else:                                               # wrap the bitmap in a one-frame .ico
        path = out + ".ico"
        hdr = struct.pack("<HHH", 0, 1, 1)
        ent = struct.pack("<BBBBHHII", w % 256, w % 256, 0, 0, 1, 32, len(blob), 22)
        open(path, "wb").write(hdr + ent + blob)
    print(path)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, struct.error):
        sys.exit(1)
