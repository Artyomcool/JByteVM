import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Prepare mods for JByteVM: one or more class directories/JARs become one shared
 * application JAR (jbv_load_jar). Lambdas, record methods, pattern switches and condy can
 * be lowered; invokedynamic, non-Java-25 classes, duplicates and library packages are refused.
 *
 *   java tools/Prepare.java INPUT... -o OUTPUT.jar [--lower-lambdas] [--lower-condy] [--jdk IGNORED]
 *   java tools/Prepare.java --unpack APP.jar -o DIRECTORY
 *
 * Classes go into one LZMA entry (jbv/classes.bin), other files stay resources. JDK 25. */
public class Prepare {
    /** Classes here belong to the runtime library; a mod copy would be shadowed. */
    static final String[] RESERVED = {"java/", "javax/", "jdk/", "sun/", "jbv/"};

    public static void main(String[] args) throws Exception {
        List<Path> inputs = new ArrayList<>();
        Path output = null;
        boolean lower = false, condy = false, unpack = false;
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "-o", "--output" -> output = Path.of(args[++i]);
                case "--lower-lambdas" -> lower = true;
                case "--lower-condy" -> condy = true;
                case "--unpack" -> unpack = true;
                case "--jdk" -> i++;   // accepted for compatibility: the running JDK is used
                default -> {
                    if (args[i].startsWith("-")) fail("unknown option " + args[i]);
                    inputs.add(Path.of(args[i]));
                }
            }
        }
        try {
            if (output == null) throw new IllegalArgumentException("-o OUTPUT is required.");
            if (Runtime.version().feature() != 25) throw new IllegalArgumentException("JDK 25 is required (running " + Runtime.version() + ").");
            if (unpack) {
                if (inputs.size() != 1 || Files.exists(output)) throw new IllegalArgumentException("--unpack takes one JAR and a new output directory.");
                JarPack.unpack(inputs.get(0), output);
            } else prepare(inputs, output, lower, condy);
        } catch (IllegalArgumentException | IOException | IllegalStateException e) {
            System.err.println(e.getMessage());
            System.exit(1);
        }
        System.out.println("Prepared " + output);
    }

    static void prepare(List<Path> sources, Path output, boolean lower, boolean condy) throws Exception {
        if (sources.isEmpty()) throw new IllegalArgumentException("No input.");
        List<Path> inputs = new ArrayList<>();
        for (Path s : sources) inputs.add(s.toAbsolutePath().normalize());
        output = output.toAbsolutePath().normalize();
        if (!output.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".jar")) throw new IllegalArgumentException("Output must be a .jar file.");
        if (Files.exists(output)) throw new IllegalArgumentException("Output already exists; use a new output path.");
        for (Path s : inputs) if (Files.isDirectory(s) && output.startsWith(s)) throw new IllegalArgumentException("Output must be outside the input directories.");
        Files.createDirectories(output.getParent());
        Path staging = Files.createTempDirectory(output.getParent(), "jbv-prepare-");
        try {
            Path unpacked = staging.resolve("input"), compiled = staging.resolve("output");
            Files.createDirectories(unpacked);
            Map<String, Path> origins = new HashMap<>();
            for (Path s : inputs) unpackInput(s, unpacked, origins);
            if (lower) LowerLambdas.lower(new String[] {unpacked.toString(), compiled.toString()});
            else copyTree(unpacked, compiled);
            if (condy) {
                Path lowered = staging.resolve("condy");
                LowerCondy.main(new String[] {compiled.toString(), lowered.toString()});
                compiled = lowered;
            }
            List<Map.Entry<String, byte[]>> classes = new ArrayList<>(), resources = new ArrayList<>();
            for (Path path : files(compiled)) {
                String name = compiled.relativize(path).toString().replace('\\', '/');
                byte[] data = Files.readAllBytes(path);
                if (!name.endsWith(".class")) { resources.add(Map.entry(name, data)); continue; }
                for (String r : RESERVED) if (name.startsWith(r)) throw new IllegalArgumentException(name + ": package is reserved for the runtime library.");
                if (ClassFiles.hasConstant(data, 17)) throw new IllegalArgumentException(name + " contains CONSTANT_Dynamic; use --lower-condy.");
                if (ClassFiles.hasIndy(data)) throw new IllegalArgumentException(name + " contains invokedynamic; use --lower-lambdas (lambdas, records, pattern switches).");
                if (ClassFiles.u16(data, 6) != 69 || ClassFiles.u16(data, 4) != 0) throw new IllegalArgumentException("Only non-preview Java 25 class files are supported: " + name);
                classes.add(Map.entry(name.substring(0, name.length() - 6), data));
            }
            Path result = staging.resolve("result.jar");
            Files.write(result, JarPack.packClasses(classes, resources));
            Files.move(result, output);
        } finally {
            Embed.deleteTree(staging);
        }
    }

    static void unpackInput(Path source, Path target, Map<String, Path> origins) throws IOException {
        if (Files.isDirectory(source)) {
            for (Path path : files(source)) put(source.relativize(path).toString().replace('\\', '/'), Files.readAllBytes(path), source, target, origins);
            return;
        }
        try (ZipFile archive = new ZipFile(source.toFile())) {
            for (ZipEntry entry : java.util.Collections.list(archive.entries()))
                if (!entry.isDirectory()) put(entry.getName(), archive.getInputStream(entry).readAllBytes(), source, target, origins);
        } catch (java.util.zip.ZipException e) {
            throw new IllegalArgumentException(source + ": " + e.getMessage());
        }
    }
    static void put(String name, byte[] data, Path source, Path target, Map<String, Path> origins) throws IOException {
        name = name.replace('\\', '/');
        String upper = name.toUpperCase(Locale.ROOT);
        if (upper.equals("META-INF/MANIFEST.MF")) return;
        if (upper.startsWith("META-INF/VERSIONS/")) throw new IllegalArgumentException("Select one class-file version before preparing a multi-release JAR.");
        if (upper.startsWith("META-INF/") && (upper.endsWith(".SF") || upper.endsWith(".RSA") || upper.endsWith(".DSA") || upper.endsWith(".EC")))
            throw new IllegalArgumentException("Signed JARs must be rebuilt and signed again after bytecode transformation.");
        Path path = target.resolve(name).normalize();
        if (!path.startsWith(target)) throw new IllegalArgumentException("Unsafe archive entry: " + name);
        if (origins.containsKey(name)) throw new IllegalArgumentException(name + " is present in both " + origins.get(name) + " and " + source + ".");
        origins.put(name, source);
        JarPack.write(path, data);
    }
    /** Regular files under a directory, by path (the order of JAR entries does not depend on it). */
    static List<Path> files(Path directory) throws IOException {
        try (Stream<Path> s = Files.walk(directory)) { return s.filter(Files::isRegularFile).sorted(Comparator.comparing(p -> directory.relativize(p).toString().replace('\\', '/'))).toList(); }
    }
    static void copyTree(Path from, Path to) throws IOException {
        for (Path p : files(from)) JarPack.write(to.resolve(from.relativize(p).toString()), Files.readAllBytes(p));
        Files.createDirectories(to);
    }
    static void fail(String message) { System.err.println(message); System.exit(2); }
}
