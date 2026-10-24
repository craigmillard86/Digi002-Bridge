#!/usr/bin/env python3
"""Extract a gzipped odc/newc cpio archive (Apple pkg Payload) into outdir."""
import sys, gzip, os, struct

def main(src, outdir):
    data = gzip.open(src, 'rb').read()
    pos = 0; n = 0
    os.makedirs(outdir, exist_ok=True)
    while pos < len(data):
        magic = data[pos:pos+6]
        if magic == b'070707':  # odc, ascii octal
            fields = data[pos+6:pos+76]
            dev, ino, mode, uid, gid, nlink, rdev = [int(fields[i*6:(i+1)*6], 8) for i in range(7)]
            mtime = int(fields[42:53], 8); namesize = int(fields[53:59], 8); filesize = int(fields[59:70], 8)
            pos += 76
            name = data[pos:pos+namesize-1].decode('utf-8', 'replace'); pos += namesize
            body = data[pos:pos+filesize]; pos += filesize
        elif magic in (b'070701', b'070702'):
            f = [int(data[pos+6+i*8:pos+14+i*8], 16) for i in range(13)]
            mode, filesize, namesize = f[1], f[6], f[11]
            pos += 110
            name = data[pos:pos+namesize-1].decode('utf-8', 'replace'); pos += namesize
            pos = (pos + 3) & ~3
            body = data[pos:pos+filesize]; pos += filesize
            pos = (pos + 3) & ~3
        else:
            raise SystemExit(f'bad magic {magic!r} at {pos}')
        if name == 'TRAILER!!!':
            break
        name = name.lstrip('./')
        dest = os.path.join(outdir, name)
        kind = mode & 0o170000
        if kind == 0o040000:
            os.makedirs(dest, exist_ok=True)
        elif kind == 0o120000:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if not os.path.lexists(dest): os.symlink(body.decode(), dest)
        elif kind == 0o100000:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            open(dest, 'wb').write(body)
            os.chmod(dest, mode & 0o777)
            n += 1
    print('extracted', n, 'files')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
