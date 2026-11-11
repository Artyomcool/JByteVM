"""Verify JBV_GC marking: every function that may allocate on the Java heap or run
Java code (and so may collect and move objects) must be marked JBV_GC, on its
prototype or its definition. Unmarked functions are guaranteed allocation-free,
so C code may keep raw object pointers across calls to them.

Static analysis over src/*.c and src/*.h: a call graph of functions and
function-like macros, seeded with the primitive GC operations and with indirect
calls through function pointers (natives, host callbacks), propagated to callers.

  python tools/check_gc.py            # report, exit 1 on unmarked GC functions
  python tools/check_gc.py --fix      # insert missing JBV_GC marks
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
# Primitive operations: allocating a Java object, running Java code, collecting.
SEEDS = {"jbv_new", "jbv_execute", "collect", "minor"}
# Calls through pointers that cannot reach the Java heap.
SAFE_INDIRECT = {"alloc", "free", "clock", "visit"}
KEYWORDS = {"if", "for", "while", "switch", "return", "sizeof", "defined", "else", "do", "case", "goto"}
IDENT = re.compile(r"[A-Za-z_]\w*")


def strip(text):
    """Blank out comments, string and char literals, keeping offsets and newlines."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j])); i = j
        elif text.startswith("//", i):
            j = text.find("\n", i); j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(c + " " * (j - i - 1) + c); i = j + 1
        else:
            out.append(c); i += 1
    return "".join(out)


def calls(body):
    """Direct callees and whether the body calls through a function pointer."""
    direct, indirect = set(), set()
    for m in re.finditer(r"(->|\.)?\s*\b([A-Za-z_]\w*)\s*\(", body):
        member, name = m.group(1), m.group(2)
        if member: indirect.add(name)
        elif name not in KEYWORDS: direct.add(name)
    for m in re.finditer(r"\(\s*\*\s*([A-Za-z_]\w*)\s*\)\s*\(", body): indirect.add(m.group(1))
    return direct, indirect


def parse(path):
    """Yield (name, prefix_start, name_offset, body) for definitions and function-like macros."""
    raw = path.read_text(encoding="utf-8", errors="replace")
    text = strip(raw)
    for m in re.finditer(r"^[ \t]*#[ \t]*define[ \t]+(\w+)\(([^)]*)\)((?:[^\n]*\\\n)*[^\n]*)", text, re.M):
        yield m.group(1), m.start(), m.start(1), m.group(3), True
    depth, i, n = 0, 0, len(text)
    while i < n:
        c = text[i]
        if c == "#" and (i == 0 or text[i - 1] == "\n"):   # skip preprocessor lines
            while i < n and (text[i] != "\n" or text[i - 1] == "\\"): i += 1
            continue
        if c == "{":
            if depth == 0:
                j = i - 1
                while j >= 0 and text[j].isspace(): j -= 1
                if j >= 0 and text[j] == ")":
                    k, d = j, 0
                    while k >= 0:
                        d += text[k] == ")"; d -= text[k] == "("
                        if d == 0: break
                        k -= 1
                    k -= 1
                    while k >= 0 and text[k].isspace(): k -= 1
                    e = k + 1
                    while k >= 0 and (text[k].isalnum() or text[k] == "_"): k -= 1
                    name = text[k + 1:e]
                    start = max(text.rfind(";", 0, k), text.rfind("}", 0, k), text.rfind("\n#", 0, k)) + 1
                    end, d = i, 0
                    while end < n:
                        d += text[end] == "{"; d -= text[end] == "}"
                        end += 1
                        if d == 0: break
                    if name and name not in KEYWORDS:
                        yield name, start, k + 1, text[i:end], False
                    i = end; continue
            depth += 1
        elif c == "}": depth -= 1
        i += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fix", action="store_true", help="insert missing JBV_GC marks")
    args = parser.parse_args()
    files = sorted(SRC.glob("*.c")) + sorted(SRC.glob("*.h"))
    defs, marked, sites = {}, set(), {}
    for path in files:
        text = strip(path.read_text(encoding="utf-8", errors="replace"))
        text = re.sub(r"__declspec\([^)]*\)", lambda m: " " * len(m.group(0)), text)
        # Prototypes and definitions carrying the mark.
        for m in re.finditer(r"\bJBV_GC\b[^;{(]*?\b(\w+)\s*\(", text): marked.add(m.group(1))
        # Prototypes: start in column 0, no assignment or return before the name.
        for m in re.finditer(r"^(?![\s#])(?!return\b)([^\n;{}()=]*?)\b(\w+)\s*\([^;{}]*\)\s*;", text, re.M):
            if m.group(2) not in KEYWORDS: sites.setdefault(m.group(2), []).append((path, m.start(1)))
        for name, start, at, body, is_macro in parse(path):
            direct, indirect = calls(body)
            entry = defs.setdefault(name, {"direct": set(), "indirect": set(), "where": [], "macro": is_macro})
            entry["direct"] |= direct; entry["indirect"] |= indirect - SAFE_INDIRECT
            entry["where"].append((path, start))
    gc = {name for name in SEEDS if name in defs}
    gc |= {name for name, d in defs.items() if d["indirect"]}
    changed = True
    while changed:
        changed = False
        for name, d in defs.items():
            if name not in gc and d["direct"] & gc:
                gc.add(name); changed = True
    internal = SEEDS | {"jbv_collect"}   # the collector's own entry points
    missing = sorted(name for name in gc if not defs[name]["macro"] and name not in marked and name not in internal)
    extra = sorted(name for name in marked if name in defs and name not in gc)
    def why(name):
        d = defs[name]
        hit = sorted(d["direct"] & gc)
        return ("calls " + ", ".join(hit[:4])) if hit else ("calls through " + ", ".join(sorted(d["indirect"])[:3]))
    for name in missing:
        path, _ = defs[name]["where"][0]
        print(f"error: {name} ({path.name}) may collect but is not marked JBV_GC: {why(name)}")
    for name in extra:
        print(f"warning: {name} is marked JBV_GC but never allocates or runs Java")
    if args.fix and missing:
        edits = {}
        for name in missing:
            targets = sites.get(name) or defs[name]["where"]
            for path, offset in targets: edits.setdefault(path, set()).add(offset)
        for path, offsets in edits.items():
            raw = path.read_text(encoding="utf-8")
            for offset in sorted(offsets, reverse=True):
                while offset < len(raw) and raw[offset] in " \t\n": offset += 1
                raw = raw[:offset] + "JBV_GC " + raw[offset:]
            path.write_text(raw, encoding="utf-8")
        print(f"marked {len(missing)} functions")
    print(f"{len(gc)} GC-capable of {len(defs)} functions/macros; {len(missing)} unmarked, {len(extra)} over-marked")
    return 1 if missing and not args.fix else 0


if __name__ == "__main__":
    sys.exit(main())
