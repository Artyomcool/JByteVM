"""Inspect actual PE section bytes and linker-map code spans (including padding)."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import struct


def inspect_image(path):
    data = path.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    machine, count, _, _, _, optional, _ = struct.unpack_from('<HHIIIHH', data, pe + 4)
    sections = []
    for i in range(count):
        at = pe + 24 + optional + i * 40
        name = data[at:at + 8].rstrip(b'\0').decode('ascii')
        virtual, rva, raw, offset = struct.unpack_from('<IIII', data, at + 8)
        sections.append(dict(name=name, virtual_bytes=virtual, raw_bytes=raw, rva=rva, offset=offset))
    report = dict(file=str(path), file_bytes=len(data), machine=hex(machine), sections=sections)
    map_path = path.with_suffix('.map')
    if map_path.is_file():
        symbols = defaultdict(list)
        pattern = re.compile(r'^\s+0001:([0-9a-fA-F]+)\s+(\S+)\s+[0-9a-fA-F]+\s+(?:f\s+)?(\S+\.obj)\s*$')
        for line in map_path.read_text().splitlines():
            match = pattern.match(line)
            if match:
                offset, name, owner = match.groups()
                symbols[int(offset, 16)].append((name, owner))
        addresses = sorted(symbols)
        sizes = defaultdict(int)
        largest = []
        end = next(s['virtual_bytes'] for s in sections if s['name'] == '.text')
        for start, stop in zip(addresses, addresses[1:] + [end]):
            entries = symbols[start]
            owners = sorted(set(owner for _, owner in entries))
            owner = owners[0] if len(owners) == 1 else 'shared: ' + ', '.join(owners)
            sizes[owner] += stop - start
            largest.append(dict(bytes=stop-start, name=entries[0][0], owner=owner))
        report['code_spans_by_object'] = dict(sorted(sizes.items(), key=lambda item: -item[1]))
        report['largest_code_spans'] = sorted(largest, key=lambda item: -item['bytes'])[:12]
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dll', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    rendered = json.dumps(inspect_image(args.dll), indent=2) + '\n'
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end='')
