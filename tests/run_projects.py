"""Compile, prepare and run the sample mods in tests/projects on HotSpot and JByteVM.

Each project is a directory pNN_name with sources in package pNN (entry pNN.Main.run()
returning a String). expected.txt overrides the HotSpot result (e.g. host natives).
Run with the x86 Python: .tools/python-x86/python.exe tests/run_projects.py --jdk ...
"""
import ctypes as C
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path
from test_vm import VM, LIB, JAVA, ROOT, OK, remaining
from test_strings import read_units
sys.path.insert(0, str(ROOT / "tools"))
from prepare import prepare

PROJECTS = ROOT / "tests/projects"
WORK = ROOT / "build/projects"
JAVAC = JAVA.parent / "javac.exe"
STATUS = ["OK","BAD_ARGUMENT","OUT_OF_MEMORY","BAD_CLASS","UNSUPPORTED_VERSION","INDY_DISABLED","UNSUPPORTED_FEATURE",
          "NOT_FOUND","LINKAGE_ERROR","DIVIDE_BY_ZERO","LIMIT_EXCEEDED","BUSY","NULL_REFERENCE","ARRAY_BOUNDS",
          "NEGATIVE_ARRAY_SIZE","ARRAY_STORE","CLASS_CAST"]
LIB.jbv_string_new_utf8.argtypes = [C.c_void_p, C.c_char_p, C.c_uint32, C.POINTER(C.c_int32)]

def natives(vm, package):
    """Host functions for projects that declare static natives (see p23)."""
    def score(handle, user, args, count, result): result[0] = args[0] * 3 + 1; return OK
    def clamp(handle, user, args, count, result): result[0] = max(args[1], min(args[2], args[0])); return OK
    vm.bind("hostScore", score, owner=f"{package}/Host", descriptor="(I)I")
    vm.bind("hostClamp", clamp, owner=f"{package}/Host", descriptor="(III)I")

def compile_project(src, out):
    files = [str(p) for p in sorted(src.rglob("*.java"))] + [str(p) for p in (PROJECTS / "_harness").rglob("*.java")]
    r = subprocess.run([str(JAVAC), "--release", "25", "-g:none", "-parameters", "-XDstringConcat=inline", "-nowarn", "-d", str(out), *files],
                       capture_output=True, text=True)
    return r.returncode == 0, (r.stdout + r.stderr).strip()

def jbv_run(jar, package, project):
    with VM(instructions=4_000_000_000) as vm:
        status = vm.load_jar(jar.read_bytes())
        if status != OK: return f"VM load_jar {STATUS[status] if status < len(STATUS) else status}", 0, vm.peak_bytes
        if (project / "natives").exists(): natives(vm, package)
        name = (package + ".Main").encode()
        ref = C.c_int32()
        assert LIB.jbv_string_new_utf8(vm.handle, name, len(name), C.byref(ref)) == OK
        start = time.perf_counter()
        status, result = vm.call("run", ref.value, owner="jbvharness/Harness", descriptor="(Ljava/lang/String;)Ljava/lang/String;")
        elapsed = time.perf_counter() - start
        if status != OK: return f"VM status {STATUS[status] if status < len(STATUS) else status}", elapsed, vm.peak_bytes
        return "".join(map(chr, read_units(vm, result))), elapsed, vm.peak_bytes

def main():
    only = set(remaining)
    if WORK.exists(): shutil.rmtree(WORK)
    rows = []
    for project in sorted(p for p in PROJECTS.iterdir() if p.is_dir() and not p.name.startswith("_")):
        if only and project.name not in only: continue
        package = project.name.split("_")[0]
        row = {"project": project.name}
        classes, jar = WORK / project.name / "classes", WORK / project.name / "app.jar"
        ok, log = compile_project(project, classes)
        if not ok: row.update(stage="javac", detail=log.splitlines()[0] if log else ""); rows.append(row); continue
        hs = subprocess.run([str(JAVA), "-cp", str(classes), "jbvharness.Harness", package + ".Main"], capture_output=True, text=True, timeout=120)
        expected = (project / "expected.txt").read_text().strip() if (project / "expected.txt").exists() else hs.stdout
        row["expected"] = expected
        try: prepare(classes, jar, JAVA.parent.parent, True, True)
        except Exception as e:
            row.update(stage="prepare", detail=str(e).splitlines()[0]); rows.append(row); continue
        row["jar_bytes"] = jar.stat().st_size
        actual, elapsed, peak = jbv_run(jar, package, project)
        row.update(actual=actual, ms=round(elapsed * 1000, 1), peak_kb=peak // 1024,
                   stage="ok" if actual == expected else "mismatch")
        rows.append(row)
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "report.json").write_text(json.dumps(rows, indent=1, ensure_ascii=False))
    for r in rows:
        line = f"{r['project']:22} {r['stage']:9}"
        if r["stage"] in ("ok", "mismatch"): line += f" {r['ms']:8.1f} ms {r['peak_kb']:6} KB jar {r['jar_bytes']:6}"
        if r["stage"] == "mismatch": line += f"\n    HotSpot: {r['expected'][:150]}\n    JByteVM: {r['actual'][:150]}"
        if r["stage"] in ("javac", "prepare"): line += "  " + r["detail"][:160]
        print(line)
    print(sum(r["stage"] == "ok" for r in rows), "of", len(rows), "match HotSpot")

if __name__ == "__main__":
    main()
