"""Write a minimal, deterministic JAR (plain ZIP: no extra fields, no comments,
fixed timestamps). Entries are LZMA (ZIP method 14), or stored when that is not
smaller: what JByteVM reads (src/jar.c). Standard ZIP tools read it too."""
from pathlib import Path
import struct
import zipfile
import lzma
import zlib

DOS_TIME, DOS_DATE = 0, (2026 - 1980) << 9 | 1 << 5 | 1


def _lzma(data):
    """ZIP method 14: version, props size 5, props (lc/lp/pb, dictionary size), raw LZMA1 stream."""
    dictionary = 1 << max(12, (len(data) - 1).bit_length())
    best = None
    for lc in range(0, 5):
        for pb in (0, 2):
            raw = lzma.compress(data, format=lzma.FORMAT_RAW, filters=[{'id': lzma.FILTER_LZMA1, 'preset': 9 | lzma.PRESET_EXTREME,
                                                                         'lc': lc, 'lp': 0, 'pb': pb, 'dict_size': dictionary}])
            packed = bytes([9, 20, 5, 0, (pb * 5) * 9 + lc]) + struct.pack('<I', dictionary) + raw
            if best is None or len(packed) < len(best): best = packed
    return best


CLASSES = 'jbv/classes.bin'


def classes_blob(classes):
    """classes: list of (internal name, bytes). Sorted by name: neighbours share
    the most strings inside DEFLATE's 32 KiB window. Read by jbv_archive_find."""
    classes = sorted(classes)
    names = [n.encode('utf-8') for n, _ in classes]
    if len(set(names)) != len(names): raise ValueError('Duplicate class in one JAR.')
    offset = 4 + sum(9 + len(n) for n in names)
    index = bytearray(struct.pack('<I', len(classes)))
    for n, (_, data) in zip(names, classes):
        if len(n) > 255: raise ValueError(f'Class name too long: {n.decode()}')
        index += struct.pack('<IIB', offset, len(data), len(n)) + n
        offset += len(data)
    return bytes(index) + b''.join(d for _, d in classes)


def pack_classes(classes, resources=()):
    """JByteVM JAR: all classes in one solid entry, resources as ordinary entries."""
    return pack([(CLASSES, classes_blob(classes)), *sorted(resources)])


def unpack(jar, directory):
    """Expand a JByteVM JAR into a plain class directory (for HotSpot and tools)."""
    with zipfile.ZipFile(jar) as z:
        for name in z.namelist():
            data = z.read(name)
            if name != CLASSES:
                (directory / name).parent.mkdir(parents=True, exist_ok=True); (directory / name).write_bytes(data); continue
            count = struct.unpack_from('<I', data)[0]; at = 4
            for _ in range(count):
                offset, size, length = struct.unpack_from('<IIB', data, at)
                target = directory / (data[at + 9:at + 9 + length].decode() + '.class'); at += 9 + length
                target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data[offset:offset + size])


def pack(entries):
    """entries: list of (name, bytes). Returns the JAR image."""
    local, central = bytearray(), bytearray()
    for name, data in entries:
        raw = name.encode('utf-8')
        packed, method = _lzma(data), 14
        if len(packed) >= len(data): packed, method = data, 0
        crc = zlib.crc32(data)
        head = struct.pack('<HHHHHIII', 63 if method == 14 else 20, 0x802 if method == 14 else 0x800, method, DOS_TIME, DOS_DATE, crc, len(packed), len(data))
        central += struct.pack('<IH', 0x02014b50, 20) + head + struct.pack('<HHHHHII', len(raw), 0, 0, 0, 0, 0, len(local)) + raw
        local += struct.pack('<I', 0x04034b50) + head + struct.pack('<HH', len(raw), 0) + raw + packed
    end = struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, len(entries), len(entries), len(central), len(local), 0)
    image = bytes(local + central + end)
    with zipfile.ZipFile(__import__('io').BytesIO(image)) as z:  # standard tools must accept it
        assert z.testzip() is None
    return image
