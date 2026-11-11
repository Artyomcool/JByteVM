"""Write a minimal, deterministic deflated JAR (plain ZIP: no extra fields,
no comments, fixed timestamps). Each entry keeps the smallest of: zlib level 9,
7-Zip's exhaustive deflate (when installed) or stored bytes."""
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zipfile
import zlib

SEVEN_ZIP = [Path(r'C:/Program Files/7-Zip/7z.exe'), Path(r'C:/Program Files (x86)/7-Zip/7z.exe')]
DOS_TIME, DOS_DATE = 0, (2026 - 1980) << 9 | 1 << 5 | 1


def _zlib(data):
    c = zlib.compressobj(9, zlib.DEFLATED, -15, 9)
    return c.compress(data) + c.flush()


def _raw_streams(jar):
    """Raw deflate streams of every entry of an existing ZIP, keyed by name."""
    out = {}
    blob = jar.read_bytes()
    with zipfile.ZipFile(jar) as z:
        for info in z.infolist():
            if info.compress_type != zipfile.ZIP_DEFLATED: continue
            at = info.header_offset
            n, e = struct.unpack_from('<HH', blob, at + 26)
            out[info.filename] = blob[at + 30 + n + e: at + 30 + n + e + info.compress_size]
    return out


def _seven_zip(entries):
    exe = next((p for p in SEVEN_ZIP if p.is_file()), None) or (shutil.which('7z') and Path(shutil.which('7z')))
    if not exe: return {}
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / 'in'
        for name, data in entries:
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_bytes(data)
        (Path(tmp) / 'list.txt').write_text('\n'.join(name for name, _ in entries) + '\n')
        subprocess.run([str(exe), 'a', '-tzip', '-mm=Deflate', '-mx=9', '-mfb=258', '-mpass=15', str(Path(tmp) / 'out.zip'),
                        '@' + str(Path(tmp) / 'list.txt')], cwd=root, check=True, stdout=subprocess.DEVNULL)
        return _raw_streams(Path(tmp) / 'out.zip')


def pack(entries):
    """entries: list of (name, bytes). Returns the JAR image."""
    better = _seven_zip(entries)
    local, central = bytearray(), bytearray()
    for name, data in entries:
        raw = name.encode('utf-8')
        packed = min((s for s in (_zlib(data), better.get(name)) if s is not None), key=len)
        method = 8
        if len(packed) >= len(data): packed, method = data, 0
        assert method == 0 or zlib.decompress(packed, -15) == data
        crc = zlib.crc32(data)
        head = struct.pack('<HHHHHIII', 20, 0x800, method, DOS_TIME, DOS_DATE, crc, len(packed), len(data))
        central += struct.pack('<IH', 0x02014b50, 20) + head + struct.pack('<HHHHHII', len(raw), 0, 0, 0, 0, 0, len(local)) + raw
        local += struct.pack('<I', 0x04034b50) + head + struct.pack('<HH', len(raw), 0) + raw + packed
    end = struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, len(entries), len(entries), len(central), len(local), 0)
    image = bytes(local + central + end)
    with zipfile.ZipFile(__import__('io').BytesIO(image)) as z:  # standard tools must accept it
        assert z.testzip() is None
    return image
