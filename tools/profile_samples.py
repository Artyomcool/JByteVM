"""Summarize jbytevm-bench JBV_SAMPLE output: samples per function (from the linker
MAP) and, given an /FAsc listing, per source line inside chosen functions.

  JBV_SAMPLE=s.txt jbytevm-bench app.jar pkg/Class method 20
  python tools/profile_samples.py s.txt build/x86/Release/jbytevm.map [interpreter.asm [function...]]
"""
import bisect
import collections
import re
import sys

def load_map(path):
    base, symbols = 0x10000000, []
    for line in open(path, encoding='latin-1'):
        m = re.match(r'\s*Preferred load address is ([0-9a-fA-F]+)', line)
        if m: base = int(m.group(1), 16)
        m = re.match(r'\s*[0-9a-fA-F]{4}:[0-9a-fA-F]{8}\s+(\S+)\s+([0-9a-fA-F]{8})\s', line)
        if m: symbols.append((int(m.group(2), 16) - base, m.group(1)))
    symbols.sort()
    return symbols

def load_listing(path, name):
    """offset -> nearest source comment, for one function of an /FAsc listing."""
    lines, inside, source, out = open(path, encoding='latin-1').read().splitlines(), False, '', []
    for line in lines:
        if re.match(r'^' + re.escape(name) + r'\s+PROC', line): inside = True; continue
        if inside and re.match(r'^' + re.escape(name) + r'\s+ENDP', line): break
        if not inside: continue
        if line.startswith(';') and ':' in line: source = line[1:].strip(); continue
        m = re.match(r'\s+([0-9a-fA-F]{5,8})\s', line)
        if m: out.append((int(m.group(1), 16), source + '  |' + line.split('\t')[-1].strip()))
    return out

def main():
    samples, symbols = open(sys.argv[1]).read().split(), load_map(sys.argv[2])
    starts = [s for s, _ in symbols]
    by_function, rvas = collections.Counter(), []
    for s in samples:
        if s == 'other': by_function['(outside jbytevm.dll)'] += 1; continue
        rva = int(s, 16); i = bisect.bisect_right(starts, rva) - 1
        name = symbols[i][1] if i >= 0 else '?'
        by_function[name] += 1; rvas.append((name, rva - symbols[i][0]))
    total = len(samples)
    print(f'{total} samples')
    for name, n in by_function.most_common(15): print(f'{100*n/total:6.1f}%  {name}')
    if len(sys.argv) > 3:
        for name in sys.argv[4:] or [by_function.most_common(1)[0][0]]:
            listing = load_listing(sys.argv[3], name)
            offsets = [o for o, _ in listing]
            lines = collections.Counter()
            for f, off in rvas:
                if f != name or not listing: continue
                i = max(bisect.bisect_right(offsets, off) - 1, 0)
                lines[listing[i][1].split('  |')[0]] += 1
            print(f'\n{name} by source line:')
            for line, n in lines.most_common(25): print(f'{100*n/total:6.1f}%  {line[:110]}')

if __name__ == '__main__':
    main()
