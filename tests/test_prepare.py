"""Public preparation pipeline: one shared JAR, bytecode, resources, errors."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from test_vm import ROOT, JAVA, CLASSES, VM, LIB, OK, remaining, has_indy
from prepare import prepare
from check_no_indy import has_constant
import jar_pack

JDK=JAVA.parent.parent

def expand(jar,work):
    target=work/(jar.stem+'-expanded');jar_pack.unpack(jar,target);return target

# Records (ObjectMethods) and pattern switches (SwitchBootstraps) of every label kind.
PATTERNS=r'''import java.util.*;
public class Patterns {
    record Empty() {}
    record Prims(boolean z, byte b, char c, short s, int i, long j, float f, double d) {}
    record Refs(String s, Object o, List<String> l) {}
    record Box<T>(T value, T other) {}
    record Nested(Prims p, Box<String> b, Empty e) {}
    record Loud(String tag) {
        public boolean equals(Object o) { System.out.print("eq" + tag + " "); return o instanceof Loud l && tag.equals(l.tag); }
        public int hashCode() { System.out.print("hash" + tag + " "); return tag.length(); }
        public String toString() { System.out.print("str" + tag + " "); return tag; }
    }
    record Order(Loud a, Loud b, Loud c) {}
    record Point(int x, int y) {}
    record Line(Point a, Point b) {}
    record Throws(int x) { public int x() { throw new IllegalStateException("boom"); } }
    enum Color { RED, GREEN { public String toString() { return "g"; } }, BLUE }
    sealed interface Expr permits Num, Add, Neg {}
    record Num(int v) implements Expr {}
    record Add(Expr l, Expr r) implements Expr {}
    record Neg(Expr e) implements Expr {}
    static String classify(Object o) {
        return switch (o) {
            case null -> "null";
            case String s when s.length() > 3 -> "long " + s;
            case String s -> "string " + s;
            case Integer i when i > 100 -> "big";
            case Color.GREEN -> "qualified green";
            case Color c when c == Color.RED -> "red";
            case Color c -> "color " + c.name();
            case Point(int x, int y) when x == y -> "diagonal " + x;
            case Point(var x, var y) -> "point " + x + y;
            case Line(Point(var a, var b), Point c) -> "line " + a + b + c;
            case Throws(int x) -> "throws " + x;
            case int[] a -> "ints " + a.length;
            case Number n -> "number " + n.intValue();
            default -> "other";
        };
    }
    static String strings(String s) { return switch (s) { case "a" -> "A"; case String t when t.startsWith("b") -> "B"; case "bc" -> "?"; case null, default -> "-"; }; }
    static String ints(Integer i) { return switch (i) { case 1 -> "one"; case Integer j when j < 0 -> "neg"; case 2 -> "two"; case null -> "null"; default -> "int"; }; }
    static String chars(Character c) { return switch (c) { case 'x' -> "x"; case Character d when Character.isDigit(d) -> "digit"; default -> "other"; }; }
    static String enums(Color c) { return switch (c) { case RED -> "r"; case Color x when x.ordinal() == 1 -> "guarded"; case null -> "null"; default -> "d"; }; }
    static int eval(Expr e) {
        return switch (e) { case Num n -> n.v(); case Add(Num(var a), Num(var b)) -> a + b; case Add(var l, var r) -> eval(l) + eval(r);
            case Neg(Neg(var inner)) -> eval(inner); case Neg(var inner) -> -eval(inner); };
    }
    public static void main(String[] args) {
        record Local(int q, String r) {}
        Object[] records = {new Empty(), new Prims(true, (byte) -3, 'q', (short) 300, -7, 1L << 40, 1.5f, -2.25),
            new Prims(false, (byte) 0, '0', (short) 0, 0, 0, Float.NaN, Double.NaN), new Prims(false, (byte) 0, '0', (short) 0, 0, 0, -0.0f, -0.0),
            new Prims(false, (byte) 0, '0', (short) 0, 0, 0, 0.0f, 0.0), new Refs(null, null, null), new Refs("s", 4, List.of("a")),
            new Box<>(null, 2L), new Nested(null, new Box<>("a", "b"), new Empty()), new Local(1, "two"), new Point(1, 2),
            new Order(new Loud("a"), new Loud("b"), new Loud("c")), new Order(new Loud("a"), new Loud("b"), new Loud("c"))};
        for (Object r : records) {
            System.out.println(r + " " + r.hashCode() + " " + r.equals(null) + " " + r.equals("x"));
            for (Object o : records) System.out.print(r.equals(o) ? "1" : "0");
            System.out.println();
        }
        Object[] values = {null, "", "abc", "abcd", 3, 101, 5L, 'x', '7', Color.RED, Color.GREEN, Color.BLUE, new Point(2, 2), new Point(1, 2),
            new Line(new Point(1, 2), new Point(3, 4)), new int[2], new Object(), new Throws(1)};
        for (Object v : values) {
            try { System.out.println(classify(v)); } catch (MatchException e) { System.out.println("MatchException " + e.getCause().getMessage()); }
            if (v == null || v instanceof String) System.out.println(strings((String) v));
            if (v == null || v instanceof Integer) System.out.println(ints((Integer) v));
            if (v instanceof Character c) System.out.println(chars(c));
            if (v == null || v instanceof Color) System.out.println(enums((Color) v));
        }
        System.out.println(strings("bc") + ints(-4) + ints(2) + chars('-') + eval(new Add(new Neg(new Neg(new Num(2))), new Add(new Num(1), new Num(3)))));
    }
}
'''
# Calls every generated helper and the real JDK bootstrap on a value pool with all restart indices.
ORACLE=r'''import java.io.*;import java.lang.classfile.*;import java.lang.classfile.instruction.*;import java.lang.constant.*;
import java.lang.invoke.*;import java.lang.reflect.*;import java.nio.file.*;import java.util.*;
public class Oracle {
    static final List<Object> pool = new ArrayList<>(Arrays.asList(null, "", "a", "b", "bc", "abc", "abcd", 0, 1, 2, 3, -1, 101, Integer.MIN_VALUE,
        0L, 5L, (short) 3, (byte) 1, 'x', '7', '\0', 0.0, -0.0, Double.NaN, 0.0f, -0.0f, Float.NaN, true, new Object(), new int[2], List.of("a")));
    static Object sample(Class<?> t, int k) {
        if (t.isPrimitive()) return Array.get(switch (t.getName()) { case "int" -> new int[]{0, 1, -1, 2}; case "long" -> new long[]{0, 1L << 40, -1};
            case "double" -> new double[]{0.0, -0.0, Double.NaN, Double.longBitsToDouble(0x7ff8000000000001L)}; case "float" -> new float[]{0f, -0f, Float.NaN};
            case "boolean" -> new boolean[]{true, false}; case "char" -> new char[]{'x', '7'}; case "byte" -> new byte[]{0, -128}; default -> new short[]{3, -2}; }, k % 2);
        List<Object> fit = pool.stream().filter(o -> o == null || t.isInstance(o)).toList();
        return fit.get(k % fit.size());
    }
    static String run(MethodHandle h, Object... args) {
        PrintStream saved = System.out; ByteArrayOutputStream log = new ByteArrayOutputStream(); System.setOut(new PrintStream(log, true));
        try { return h.invokeWithArguments(args) + "|" + log; } catch (Throwable t) { return t.getClass().getName() + "|" + log; } finally { System.setOut(saved); }
    }
    public static void main(String[] args) throws Throwable {
        List<ClassModel> models = new ArrayList<>(); List<Class<?>> classes = new ArrayList<>();
        try (var s = Files.walk(Path.of(args[0]))) { for (Path p : s.filter(p -> p.toString().endsWith(".class")).sorted().toList()) models.add(ClassFile.of().parse(p)); }
        for (ClassModel m : models) classes.add(Class.forName(m.thisClass().asInternalName().replace('/', '.')));
        for (Class<?> c : classes) if (c.isEnum()) pool.addAll(Arrays.asList(c.getEnumConstants()));
        for (int round = 0; round < 3; round++) for (Class<?> c : classes) if (!c.isEnum() && !Modifier.isAbstract(c.getModifiers()))
            for (Constructor<?> k : c.getDeclaredConstructors()) for (int v = 0; v < 4 && (round == 0 || k.getParameterCount() > 0); v++) {
                Object[] a = new Object[k.getParameterCount()]; for (int i = 0; i < a.length; i++) a[i] = sample(k.getParameterTypes()[i], v + i * (round + 1));
                try { k.setAccessible(true); pool.add(k.newInstance(a)); } catch (InvocationTargetException | IllegalArgumentException e) {}
            }
        int sites = 0, checks = 0, failures = 0;
        for (int index = 0; index < models.size(); index++) {
            Class<?> c = classes.get(index); MethodHandles.Lookup lookup = MethodHandles.privateLookupIn(c, MethodHandles.lookup());
            Set<Integer> seen = new HashSet<>(); int helper = 0;
            for (MethodModel mm : models.get(index).methods()) if (mm.code().isPresent()) for (CodeElement e : mm.code().get()) {
                if (!(e instanceof InvokeDynamicInstruction indy) || !seen.add(indy.invokedynamic().index()) || indy.bootstrapMethod().owner().displayName().equals("LambdaMetafactory")) continue;
                MethodType type = indy.typeSymbol().resolveConstantDesc(lookup); List<Object> bsm = new ArrayList<>(List.of(lookup, indy.name().stringValue(), type));
                for (ConstantDesc a : indy.bootstrapArgs()) bsm.add(a.resolveConstantDesc(lookup));
                MethodHandle real = ((CallSite) indy.bootstrapMethod().resolveConstantDesc(lookup).invokeWithArguments(bsm)).dynamicInvoker();
                MethodHandle ours = lookup.findStatic(c, "$jbv$indy$" + helper++, type); sites++;
                Class<?> first = type.parameterType(0), box = MethodType.methodType(first).wrap().returnType();
                List<Object[]> calls = new ArrayList<>();
                for (Object a : pool) if (first.isPrimitive() ? a != null && a.getClass() == box : a == null || first.isInstance(a)) {
                    if (indy.name().stringValue().equals("equals")) { if (a != null) for (Object b : pool) calls.add(new Object[]{a, b}); }
                    else if (type.parameterCount() == 1) { if (a != null) calls.add(new Object[]{a}); }
                    else for (int r = -1; r <= indy.bootstrapArgs().size() + 1; r++) calls.add(new Object[]{a, r});
                }
                for (Object[] call : calls) { checks++; String x = run(real, call), y = run(ours, call);
                    if (!x.equals(y) && failures++ < 10) System.out.println("MISMATCH " + c.getName() + " " + indy.name() + " " + Arrays.deepToString(call) + ": " + x + " vs " + y); }
            }
        }
        System.out.println(sites + " sites, " + checks + " checks, " + failures + " mismatches");
        System.exit(failures > 0 ? 1 : 0);
    }
}
'''

class PrepareTests(unittest.TestCase):
    def test_records_and_pattern_switches(self):
        javac=str(JAVA.parent/'javac.exe');lower=[str(JAVA),str(ROOT/'tools/LowerLambdas.java')]
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary);(work/'src').mkdir();(work/'oracle').mkdir();source=work/'classes'
            (work/'src/Patterns.java').write_text(PATTERNS);(work/'oracle/Oracle.java').write_text(ORACLE)
            subprocess.run([javac,'--release','25','-XDstringConcat=inline','-d',str(source),str(work/'src/Patterns.java')],check=True)
            subprocess.run([javac,'--release','25','-d',str(work/'oracle'),str(work/'oracle/Oracle.java')],check=True)
            self.assertTrue(any(has_indy(p.read_bytes()) for p in source.glob('*.class')))
            output=work/'prepared.jar';prepare(source,output,JDK,True)
            expanded=expand(output,work)
            for path in expanded.rglob('*.class'):self.assertFalse(has_indy(path.read_bytes()),path)
            original=subprocess.run([str(JAVA),'-cp',str(source),'Patterns'],capture_output=True,text=True,check=True)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(expanded),'Patterns'],capture_output=True,text=True,check=True)
            self.assertEqual(actual.stdout,original.stdout)
            self.assertIn('Prims[z=false, b=0, c=0, s=0, i=0, j=0, f=-0.0, d=-0.0]',actual.stdout)
            self.assertIn('MatchException boom',actual.stdout);self.assertIn('eqc eqb eqa',actual.stdout)
            oracle=subprocess.run([str(JAVA),'-Xverify:all','-cp',f'{expanded};{work/"oracle"}','Oracle',str(source)],capture_output=True,text=True)
            self.assertEqual(oracle.returncode,0,oracle.stdout+oracle.stderr);self.assertRegex(oracle.stdout,r'[1-9]\d+ sites, [1-9]\d+ checks, 0 mismatches')
            # Unsupported bootstraps are named; only string concatenation suggests -XDstringConcat=inline.
            concat=work/'concat';concat.mkdir();shutil.copy2(CLASSES/'Concat.class',concat)
            result=subprocess.run([*lower,str(concat),str(work/'concat-out')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertIn('-XDstringConcat=inline',result.stderr)
            unknown=work/'unknown';unknown.mkdir()
            data=(source/'Patterns$Point.class').read_bytes();self.assertIn(b'java/lang/runtime/ObjectMethods',data)
            (unknown/'Patterns$Point.class').write_bytes(data.replace(b'java/lang/runtime/ObjectMethods',b'java/lang/runtime/ObjectMethodz'))
            result=subprocess.run([*lower,str(unknown),str(work/'unknown-out')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertIn('Unsupported invokedynamic bootstrap java.lang.runtime.ObjectMethodz.bootstrap',result.stderr)
            self.assertNotIn('stringConcat',result.stderr)
            preview=work/'preview';(work/'Preview.java').write_text('class Preview { static int f(Object o) { return switch (o) { case int i -> i; default -> 0; }; } }')
            subprocess.run([javac,'--release','25','--enable-preview','-XDstringConcat=inline','-d',str(preview),str(work/'Preview.java')],check=True,capture_output=True)
            result=subprocess.run([*lower,str(preview),str(work/'preview-out')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertIn('preview feature',result.stderr)
            self.assertFalse((work/'concat-out').exists() or (work/'unknown-out').exists() or (work/'preview-out').exists())

    def test_condy_and_lambdas_together(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary);source=work/'source';shutil.copytree(ROOT/'build/lambda-original',source)
            for p in CLASSES.glob('Condy*.class'):shutil.copy2(p,source)
            shutil.copy2(CLASSES/'NumericOracle.class',source)
            output=work/'prepared.jar'
            with self.assertRaisesRegex(ValueError,'CONSTANT_Dynamic'):prepare(source,output,JDK,True)
            self.assertFalse(output.exists())
            prepare(source,output,JDK,True,True)
            expanded=expand(output,work)
            for path in expanded.rglob('*.class'):
                self.assertFalse(has_constant(path.read_bytes(),17),path);self.assertFalse(has_indy(path.read_bytes()),path)
            original=subprocess.run([str(JAVA),'-cp',str(source),'LambdaValues'],capture_output=True,check=True)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(expanded),'LambdaValues'],capture_output=True,check=True)
            self.assertEqual(actual.stdout,original.stdout)
            result=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(expanded),'NumericOracle'],input='CondyExtra#lifecycle (I)I 0\n',text=True,capture_output=True,check=True)
            self.assertEqual(int(result.stdout.strip(),16),7)

    def test_shared_jar_runs_on_jbytevm(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary)
            source=work/'source';shutil.copytree(ROOT/'build/lambda-original',source)
            payload=b'configuration\x00\xff\n';(source/'mod.dat').write_bytes(payload)
            archive=work/'source.jar'
            with zipfile.ZipFile(archive,'w') as jar:
                for path in source.rglob('*'):
                    if path.is_file():jar.write(path,path.relative_to(source).as_posix())
            # A second mod as a plain directory: both end up in one JAR.
            other=work/'other';other.mkdir();shutil.copy2(CLASSES/'Core.class',other)
            target=work/'prepared.jar';prepare([archive,other],target,JDK,True)
            with zipfile.ZipFile(target) as jar:
                self.assertEqual(jar.read('mod.dat'),payload)
                self.assertEqual(sorted(jar.namelist()),['jbv/classes.bin','mod.dat'])
            oracle=subprocess.run([str(JAVA),'-cp',str(source),'LambdaValues'],capture_output=True,text=True,check=True)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(expand(target,work)),'LambdaValues'],capture_output=True,text=True,check=True)
            self.assertEqual(actual.stdout,oracle.stdout)
            expected=[int(s) for s in oracle.stdout.splitlines()];cases=[(m,n) for n in [0,1,-1,17,12345] for m in ['basic','advanced','errors']]
            data=target.read_bytes()
            with VM() as vm:
                self.assertEqual(vm.load_jar(data),OK)
                self.assertNotEqual(vm.load_jar(data),OK)  # one shared JAR per VM
                for (m,n),value in zip(cases,expected):
                    self.assertEqual(vm.call(m,n,owner='LambdaValues'),(OK,value),(m,n));self.assertEqual(LIB.jbv_collect(vm.handle),OK)
                self.assertEqual(vm.call('negate',5)[0],OK)
                self.assertNotEqual(vm.load_name('Core'),OK)  # already provided by the JAR
            with VM() as vm:   # resources outlive the host's buffer
                import ctypes as C
                buffer=C.create_string_buffer(data);self.assertEqual(LIB.jbv_load_jar(vm.handle,buffer,len(data)),OK)
                C.memset(buffer,0x5a,len(data));del buffer
                LIB.jbv_string_new_utf8.argtypes=[C.c_void_p,C.c_char_p,C.c_uint32,C.POINTER(C.c_int32)]
                LIB.jbv_array_read.argtypes=[C.c_void_p,C.c_int32,C.c_uint32,C.c_uint32,C.POINTER(C.c_uint64)]
                for name,expected in (('mod.dat',payload),('missing.dat',None)):
                    ref=C.c_int32();self.assertEqual(LIB.jbv_string_new_utf8(vm.handle,name.encode(),len(name),C.byref(ref)),OK)
                    status,array=vm.call('resource',ref.value,owner='jbv/runtime/Support',descriptor='(Ljava/lang/String;)[B')
                    self.assertEqual(status,OK)
                    if expected is None:self.assertEqual(array,0);continue
                    out=(C.c_uint64*len(expected))()
                    self.assertEqual(LIB.jbv_array_read(vm.handle,array,0,len(expected),out),OK)
                    self.assertEqual(bytes(x&255 for x in out),expected)
            with VM() as vm:
                broken=bytearray(data);broken[len(broken)//3]^=0x55
                self.assertNotEqual(vm.load_jar(bytes(broken)),OK)
            with self.assertRaisesRegex(ValueError,'already exists'):prepare(source,target,JDK,True)

    def test_rejected_input_leaves_no_output(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary);source=work/'source';source.mkdir();output=work/'result.jar'
            shutil.copy2(CLASSES/'Concat.class',source)
            with self.assertRaisesRegex(ValueError,'invokedynamic'):prepare(source,output,JDK,False)
            self.assertFalse(output.exists())
            with self.assertRaises(subprocess.CalledProcessError):prepare(source,output,JDK,True)
            self.assertFalse(output.exists())
            with self.assertRaisesRegex(ValueError,'\.jar'):prepare(source,work/'directory',JDK,False)
            twin=work/'twin';twin.mkdir();shutil.copy2(CLASSES/'Concat.class',twin)
            with self.assertRaisesRegex(ValueError,'present in both'):prepare([source,twin],output,JDK,False)
            reserved=work/'reserved';(reserved/'java/lang').mkdir(parents=True);shutil.copy2(CLASSES/'Core.class',reserved/'java/lang/Core.class')
            with self.assertRaisesRegex(ValueError,'reserved'):prepare(reserved,output,JDK,False)
            self.assertFalse(output.exists())
            archive=work/'unsafe.jar'
            for name in ['../escape','META-INF/VERSIONS/25/Mod.class','META-INF/MOD.SF']:
                with zipfile.ZipFile(archive,'w') as jar:jar.writestr(name,b'data')
                with self.assertRaises(ValueError):prepare(archive,output,JDK,False)
                self.assertFalse(output.exists())
                self.assertFalse((work/'escape').exists())

if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
