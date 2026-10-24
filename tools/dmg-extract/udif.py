#!/usr/bin/env python3
"""Minimal UDIF (.dmg) to raw image converter. Handles zero, raw, zlib, bzip2 chunks."""
import sys, struct, plistlib, zlib, bz2

def main(src, dst):
    data = open(src, 'rb').read()
    koly = data[-512:]
    assert koly[:4] == b'koly', 'no koly trailer'
    # offsets: XMLOffset at 216, XMLLength at 224 (big-endian u64)
    xml_off, xml_len = struct.unpack('>QQ', koly[216:232])
    pl = plistlib.loads(data[xml_off:xml_off+xml_len])
    blkx = pl['resource-fork']['blkx']
    out = open(dst, 'wb')
    total = 0
    for entry in blkx:
        mish = entry['Data']
        assert mish[:4] == b'mish'
        sector_number = struct.unpack('>Q', mish[8:16])[0]
        nchunks = struct.unpack('>I', mish[200:204])[0]
        print(f"blkx {entry['Name']!r}: start sector {sector_number}, {nchunks} chunks")
        pos = 204
        for i in range(nchunks):
            etype, comment, sec, seccount, coff, clen = struct.unpack('>IIQQQQ', mish[pos:pos+40])
            pos += 40
            if etype == 0xffffffff:  # terminator
                break
            abs_off = (sector_number + sec) * 512
            if etype in (0x00000000, 0x00000002):  # zero fill / ignore
                chunk = b'\0' * (seccount * 512)
            elif etype == 0x00000001:  # raw
                chunk = data[coff:coff+clen]
            elif etype == 0x80000005:  # zlib
                chunk = zlib.decompress(data[coff:coff+clen])
            elif etype == 0x80000006:  # bzip2
                chunk = bz2.decompress(data[coff:coff+clen])
            elif etype == 0x7ffffffe:  # comment
                continue
            else:
                raise SystemExit(f'unsupported chunk type {etype:#x}')
            out.seek(abs_off)
            out.write(chunk)
            total = max(total, abs_off + len(chunk))
    out.close()
    print('wrote', total, 'bytes')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
