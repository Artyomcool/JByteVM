import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import javax.tools.ToolProvider;

/** Compile the class library (classpath/) and embed it in the VM as an LZMA-compressed JAR:
 *   java tools/Embed.java BUILD_DIRECTORY
 * writes BUILD_DIRECTORY/classpath.jar and generated_classpath.asm (assembled into the DLL),
 * and classpath-sizes.txt (class bytes, JAR bytes). Run by CMake; needs JDK 25. */
public class Embed {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) fail("Usage: java tools/Embed.java BUILD_DIRECTORY");
        if (Runtime.version().feature() != 25) fail("JDK 25 is required (running " + Runtime.version() + ").");
        Path root = System.getProperty("jbv.root") != null ? Path.of(System.getProperty("jbv.root")).toAbsolutePath() : findRoot();
        Path build = Path.of(args[0]).toAbsolutePath().normalize(), source = root.resolve("classpath");
        // Character tables from this JDK (the file only changes with the JDK's Unicode version)
        GenerateUnicode.main(new String[] {source.resolve("jbv/runtime/Unicode.java").toString()});
        Path classes = build.resolve("classpath");
        if (!classes.startsWith(root.resolve("build")) && !classes.startsWith(build)) fail("The class output must stay in the build directory.");
        deleteTree(classes);   // obsolete classes (inner ones included) must not survive
        Files.createDirectories(classes);
        List<String> sources;
        try (Stream<Path> s = Files.walk(source)) { sources = s.filter(p -> p.toString().endsWith(".java")).map(Path::toString).sorted().toList(); }
        List<String> javac = new ArrayList<>(List.of("--release", "25", "-g:none", "-XDstringConcat=inline", "-Xlint:-removal",
            "--patch-module", "java.base=" + source, "-d", classes.toString()));
        javac.addAll(sources);
        if (ToolProvider.getSystemJavaCompiler().run(null, null, null, javac.toArray(String[]::new)) != 0) fail("javac failed");
        List<Map.Entry<String, byte[]>> entries = new ArrayList<>();
        long imageBytes = 0;
        List<Path> files;
        try (Stream<Path> s = Files.walk(classes)) { files = s.filter(p -> p.toString().endsWith(".class")).sorted(Comparator.comparing(Path::toString)).toList(); }
        for (Path file : files) {
            byte[] data = ClassFiles.withoutStackMaps(Files.readAllBytes(file));
            if (ClassFiles.hasIndy(data)) fail("Library must not contain invokedynamic: " + file);
            String name = classes.relativize(file).toString().replace('\\', '/');
            entries.add(Map.entry(name.substring(0, name.length() - 6), data));
            imageBytes += data.length;
        }
        byte[] jar = JarPack.packClasses(entries, List.of());
        Files.write(build.resolve("classpath.jar"), jar);
        StringBuilder asm = new StringBuilder("; Generated: the class library as a deflated JAR (also written to classpath.jar).\n"
            + ".686\n.model flat, C\nPUBLIC jbv_library_jar, jbv_library_jar_size\n.const\njbv_library_jar_size DD " + jar.length + "\njbv_library_jar LABEL BYTE\n");
        for (int off = 0; off < jar.length; off += 32) {
            asm.append("    DB ");
            for (int i = off; i < Math.min(off + 32, jar.length); i++) asm.append(i == off ? "" : ",").append(jar[i] & 0xFF);
            asm.append('\n');
        }
        asm.append("END\n");
        Files.writeString(build.resolve("generated_classpath.asm"), asm.toString(), StandardCharsets.UTF_8);
        Files.writeString(build.resolve("classpath-sizes.txt"), imageBytes + " " + jar.length + "\n");
        System.out.println("Embedded class library: " + entries.size() + " classes, " + imageBytes + " bytes, JAR " + jar.length + " bytes");
    }
    static Path findRoot() {
        Path here = Path.of("").toAbsolutePath();
        for (Path p = here; p != null; p = p.getParent()) if (Files.isDirectory(p.resolve("classpath")) && Files.isDirectory(p.resolve("src"))) return p;
        fail("Run from the JByteVM directory (or pass -Djbv.root=...).");
        return null;
    }
    static void deleteTree(Path path) throws IOException {
        if (!Files.exists(path)) return;
        try (Stream<Path> s = Files.walk(path)) { for (Path p : s.sorted(Comparator.reverseOrder()).toList()) Files.delete(p); }
    }
    static void fail(String message) { System.err.println("Embed: " + message); System.exit(1); }
}
