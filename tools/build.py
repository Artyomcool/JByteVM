"""Build the Windows interpreter (x86 by default) with Visual Studio tools."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
from size_breakdown import inspect_image
import embed_classpath

ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], cwd=ROOT, check=True, **kwargs)


def find_cmake():
    if shutil.which("cmake"):
        return shutil.which("cmake")
    vswhere = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    install = run([vswhere, "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], capture_output=True, text=True).stdout.strip()
    cmake = Path(install) / "Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe"
    if not install or not cmake.is_file():
        raise SystemExit("Install Visual Studio 2022 Build Tools (C++ and CMake).")
    return cmake


def find_jdk(explicit):
    choices = [Path(explicit)] if explicit else []
    if os.environ.get("JAVA_HOME"):
        choices.append(Path(os.environ["JAVA_HOME"]))
    choices.extend(sorted((ROOT / ".tools").glob("jdk-25*")))
    if shutil.which("javac"):
        choices.append(Path(shutil.which("javac")).resolve().parent.parent)
    for path in choices:
        javac = path / "bin/javac.exe"
        if javac.is_file():
            version = run([javac, "-version"], capture_output=True, text=True).stdout.strip()
            if version.startswith("javac 25"):
                return path.resolve()
    raise SystemExit("JDK 25 is required; pass --jdk PATH or set JAVA_HOME.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jdk", type=Path)
    parser.add_argument("--test", action="store_true")
    parser.add_argument("--profile", choices=("full","text","core"), default="full")
    parser.add_argument("--gc-stress", type=int, nargs="?", const=4, default=0, metavar="N", help="testing: collect and move objects every N allocations (default 4)")
    parser.add_argument("--arch", choices=("x86", "x64"), default="x86")
    parser.add_argument("--test-python", type=Path, help="Python matching the target architecture for ctypes tests")
    args = parser.parse_args()
    jdk = find_jdk(args.jdk)
    cmake = find_cmake()
    build = ROOT / "build" / (args.arch + ("" if args.profile == "full" else "-" + args.profile) + ("-stress" if args.gc_stress else ""))
    build.mkdir(parents=True, exist_ok=True)
    classpath_bytes, jar_bytes = embed_classpath.build(jdk, build) if args.profile == "full" else (0, 0)
    platform = "Win32" if args.arch == "x86" else "x64"
    run([cmake, "-S", ROOT, "-B", build, "-G", "Visual Studio 17 2022", "-A", platform, "-DJBV_PROFILE=" + args.profile, "-DJBV_GC_STRESS=" + str(args.gc_stress)])
    run([cmake, "--build", build, "--config", "Release"])
    classes = ROOT / "build/classes"
    classes.mkdir(parents=True, exist_ok=True)
    run([jdk / "bin/javac.exe", "--release", "25", "-g:none", "-d", classes, *sorted((ROOT / "tests/java").rglob("*.java"))])
    run([jdk / "bin/java.exe", ROOT / "tools/GenerateCondy.java", classes])
    if args.profile == "full": run([jdk / "bin/java.exe", ROOT / "tools/LowerCondy.java", classes, ROOT / "build/condy-lowered"])
    run([jdk / "bin/javac.exe", "--release", "25", "-g:source,lines", "-XDstringConcat=inline", "-d", classes, ROOT / "tests/java/Diagnostics.java"])
    if args.test:
        original = ROOT / "build/lambda-original"
        original.mkdir(parents=True, exist_ok=True)
        run([jdk / "bin/javac.exe", "--release", "25", "-g:none", "-XDstringConcat=inline", "-d", original, *sorted((ROOT / "tests/lambda").glob("*.java"))])
        run([jdk / "bin/java.exe", ROOT / "tools/LowerLambdas.java", original, ROOT / "build/lambda-lowered"])
    run([jdk / "bin/javac.exe", "--release", "25", "-g:none", "-XDstringConcat=inline", "-d", classes, ROOT / "tests/java/Strings.java"])
    run([jdk / "bin/javac.exe", "--release", "25", "-g:none", "-parameters", "-XDstringConcat=inline", "-d", classes, ROOT / "tests/java/GenericValues.java"])
    # An explicit compiler experiment, not a supported Java language option.
    inline = ROOT / "build/concat-inline"
    inline.mkdir(parents=True, exist_ok=True)
    run([jdk / "bin/javac.exe", "--release", "25", "-g:none", "-XDstringConcat=inline", "-d", inline, ROOT / "tests/java/Concat.java"])
    run([build / "Release/jbytevm-demo.exe", classes / "Core.class"])
    run([build / "Release/jbytevm-native-demo.exe", classes / "NativeDemo.class"])
    report = {
        "profile": args.profile,
        "architecture": args.arch,
        "classpath_class_bytes": classpath_bytes,
        "embedded_jar_bytes": jar_bytes,
        "runtime_dll_bytes": (build / "Release/jbytevm.dll").stat().st_size,
        "demo_host_exe_bytes": (build / "Release/jbytevm-demo.exe").stat().st_size,
        "demo_class_bytes": (classes / "Core.class").stat().st_size,
        "jdk": run([jdk / "bin/javac.exe", "-version"], capture_output=True, text=True).stdout.strip(),
    }
    report["demo_distribution_bytes"] = sum(report[key] for key in ("runtime_dll_bytes", "demo_host_exe_bytes", "demo_class_bytes"))
    report["native_demo_host_bytes"] = (build / "Release/jbytevm-native-demo.exe").stat().st_size
    report["native_demo_class_bytes"] = (classes / "NativeDemo.class").stat().st_size
    report["native_demo_distribution_bytes"] = sum(report[key] for key in ("runtime_dll_bytes", "native_demo_host_bytes", "native_demo_class_bytes"))
    (build / "size-report.json").write_text(json.dumps(report, indent=2) + "\n")
    (build / "image-breakdown.json").write_text(json.dumps(inspect_image(build / "Release/jbytevm.dll"), indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    if args.test:
        # Every function that may collect (and move objects) must be marked JBV_GC.
        # The checker is Java, run on JByteVM itself (jbytevm-run with jbvhost.Host file natives).
        checker = ROOT / "build/tools/checkgc"
        shutil.rmtree(checker, ignore_errors=True)
        run([jdk / "bin/javac.exe", "--release", "25", "-g:none", "-XDstringConcat=inline", "-d", checker / "classes", ROOT / "tools/jbvhost/Host.java", ROOT / "tools/checkgc/CheckGc.java"])
        run([sys.executable, ROOT / "tools/prepare.py", checker / "classes", "-o", checker / "checkgc.jar", "--lower-lambdas", "--jdk", jdk])
        if args.profile == "full": run([build / "Release/jbytevm-run.exe", checker / "checkgc.jar", "checkgc/CheckGc", ROOT / "src"])
        pointer_size = 4 if args.arch == "x86" else 8
        python = args.test_python
        if not python:
            python = Path(sys.executable) if struct.calcsize("P") == pointer_size else ROOT / (".tools/python-" + args.arch + "/python.exe")
        if not python.is_file():
            raise SystemExit(f"Tests need {args.arch} Python: pass --test-python PATH.")
        actual_size = run([python, "-c", "import struct; print(struct.calcsize('P'))"], capture_output=True, text=True).stdout.strip()
        if actual_size != str(pointer_size):
            raise SystemExit(f"{python} does not match the {args.arch} target; pass --test-python PATH.")
        suites = ["test_vm.py", "test_numbers.py", "test_native.py", "test_strings.py", "test_library.py", "test_collections.py", "test_access.py", "test_dynamic.py", "test_reflection.py", "test_diagnostics.py", "test_lambdas.py", "test_util.py", "test_collections2.py", "test_stringvalues.py", "test_text.py", "test_generics.py", "test_prepare.py"]
        if args.profile != "full":
            suites = ["test_vm.py", "test_numbers.py", "test_native.py", "test_access.py"]
            if args.profile == "text": suites.append("test_strings.py")
        if args.arch == "x86":
            suites.append("test_typed.py")
        suites.append("test_memory.py")
        for suite in suites:
            run([python, ROOT / "tests" / suite, "--jdk", jdk, "--build", build, "--arch", args.arch])


if __name__ == "__main__":
    main()
