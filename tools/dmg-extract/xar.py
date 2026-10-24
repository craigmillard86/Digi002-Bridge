#!/usr/bin/env python3
"""Extract a xar archive found at a byte offset inside an image file."""
import sys, struct, zlib, os, bz2, lzma
import xml.etree.ElementTree as ET

def main(img, offset, outdir):
    f = open(img, 'rb')
    f.seek(offset)
    hdr = f.read(28)
    magic, hsize, ver, toc_clen, toc_ulen, cksum = struct.unpack('>4sHHQQI', hdr)
    assert magic == b'xar!'
    f.seek(offset + hsize)
    toc = zlib.decompress(f.read(toc_clen))
    heap = offset + hsize + toc_clen
    root = ET.fromstring(toc)
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, '_toc.xml'), 'wb').write(toc)

    def walk(node, path):
        for fe in node.findall('file'):
            name = fe.findtext('name')
            p = os.path.join(path, name)
            typ = fe.findtext('type')
            if typ == 'directory':
                os.makedirs(os.path.join(outdir, p), exist_ok=True)
                walk(fe, p)
            elif typ == 'file':
                d = fe.find('data')
                if d is None:
                    continue
                off = int(d.findtext('offset')); length = int(d.findtext('length'))
                size = int(d.findtext('size'))
                enc = d.find('encoding').get('style')
                f.seek(heap + off)
                raw = f.read(length)
                if 'gzip' in enc: raw = zlib.decompress(raw)
                elif 'bzip2' in enc: raw = bz2.decompress(raw)
                elif 'lzma' in enc or 'xz' in enc: raw = lzma.decompress(raw)
                assert len(raw) == size, (p, len(raw), size)
                open(os.path.join(outdir, p), 'wb').write(raw)
                print(f'{size:>10}  {p}')
            else:
                print('skip', typ, p)
    walk(root.find('toc'), '')

if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]), sys.argv[3])
