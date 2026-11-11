"""Reject InvokeDynamic constant-pool entries in compiled classes (or JARs).

This build-time gate does not transform lambdas and is not a class verifier.
"""
import argparse
from pathlib import Path
import struct
import sys
import zipfile


def has_constant(data, wanted):
    if len(data) < 10 or data[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError("not a class file")
    count = struct.unpack_from(">H", data, 8)[0]
    if not count:
        raise ValueError("empty constant pool")
    index, pos = 1, 10
    while index < count:
        if pos >= len(data):
            raise ValueError("truncated constant pool")
        tag = data[pos]
        pos += 1
        if tag == wanted:
            return True
        if tag == 1:
            if pos + 2 > len(data):
                raise ValueError("truncated UTF8 length")
            size = struct.unpack_from(">H", data, pos)[0]
            pos += 2 + size
        elif tag in (3, 4, 9, 10, 11, 12, 17, 18):
            pos += 4
        elif tag in (5, 6):
            pos += 8
            index += 1
            if index >= count:
                raise ValueError("missing second constant pool slot")
        elif tag in (7, 8, 16, 19, 20):
            pos += 2
        elif tag == 15:
            pos += 3
        else:
            raise ValueError(f"unknown constant pool tag {tag}")
        if pos > len(data):
            raise ValueError("truncated constant pool entry")
        index += 1
    return False


def has_indy(data):
    return has_constant(data, 18)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    failed, checked = False, 0

    def check(label, data):
        nonlocal failed, checked
        checked += 1
        try:
            if has_indy(data):
                print(f"{label}: invokedynamic is disabled", file=sys.stderr)
                failed = True
        except ValueError as error:
            print(f"{label}: {error}", file=sys.stderr)
            failed = True

    for path in args.paths:
        files = sorted(path.rglob("*.class")) if path.is_dir() else [path]
        for file in files:
            try:
                if file.suffix.lower() == ".jar":
                    with zipfile.ZipFile(file) as jar:
                        for name in jar.namelist():
                            if name.endswith(".class"):
                                check(f"{file}!{name}", jar.read(name))
                else:
                    check(file, file.read_bytes())
            except (OSError, zipfile.BadZipFile) as error:
                print(f"{file}: {error}", file=sys.stderr)
                failed = True
    if not checked:
        print("no class files found", file=sys.stderr)
        failed = True
    print(f"Checked {checked} class files.")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
