package checkgc;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import jbvhost.Host;

/**
 * Verifies JBV_GC marking: every function that may allocate on the Java heap or run
 * Java code (and so may collect and move objects) must be marked JBV_GC, on its
 * prototype or its definition. Unmarked functions are guaranteed allocation-free, so C
 * code may keep raw object pointers across calls to them.
 *
 * Builds a call graph of functions and function-like macros in src/*.c and src/*.h,
 * seeded with the primitive GC operations and with indirect calls through function
 * pointers (natives, host callbacks), and propagates it to callers.
 *
 * Runs on JByteVM itself: jbytevm-run checkgc.jar checkgc/CheckGc SRC_DIR [--fix]
 */
public final class CheckGc {
    /** Primitive operations: allocating a Java object, running Java code, collecting. */
    static final Set<String> SEEDS = Set.of("jbv_new", "jbv_execute", "collect", "minor");
    /** Calls through pointers that cannot reach the Java heap. */
    static final Set<String> SAFE_INDIRECT = Set.of("alloc", "free", "clock", "visit");
    static final Set<String> KEYWORDS = Set.of("if", "for", "while", "switch", "return", "sizeof", "defined", "else", "do", "case", "goto");
    static final Pattern MACRO = Pattern.compile("^[ \\t]*#[ \\t]*define[ \\t]+(\\w+)\\(([^)]*)\\)((?:[^\\n]*\\\\\\n)*[^\\n]*)", Pattern.MULTILINE);
    static final Pattern CALL = Pattern.compile("(->|\\.)?\\s*\\b([A-Za-z_]\\w*)\\s*\\(");
    static final Pattern POINTER_CALL = Pattern.compile("\\(\\s*\\*\\s*([A-Za-z_]\\w*)\\s*\\)\\s*\\(");
    static final Pattern MARK = Pattern.compile("\\bJBV_GC\\b[^;{(]*?\\b(\\w+)\\s*\\(");
    static final Pattern PROTOTYPE = Pattern.compile("^([^\\n;{}()=]*?)\\b(\\w+)\\s*\\([^;{}]*\\)\\s*;", Pattern.MULTILINE);
    static final Pattern DECLSPEC = Pattern.compile("__declspec\\([^)]*\\)");

    record Site(String file, int offset) {}
    static final class Def {
        final Set<String> direct = new HashSet<>(), indirect = new HashSet<>();
        final List<Site> where = new ArrayList<>();
        boolean macro;
    }

    /** Blanks comments, string and char literals, keeping offsets and newlines. */
    static String strip(String text) {
        StringBuilder out = new StringBuilder(text.length());
        int i = 0, n = text.length();
        while (i < n) {
            char c = text.charAt(i);
            if (text.startsWith("/*", i)) {
                int j = text.indexOf("*/", i + 2); j = j < 0 ? n : j + 2;
                for (; i < j; i++) out.append(text.charAt(i) == '\n' ? '\n' : ' ');
            } else if (text.startsWith("//", i)) {
                int j = text.indexOf('\n', i); j = j < 0 ? n : j;
                for (; i < j; i++) out.append(' ');
            } else if (c == '"' || c == '\'') {
                int j = i + 1;
                while (j < n && text.charAt(j) != c) j += text.charAt(j) == '\\' ? 2 : 1;
                out.append(c);
                for (int k = i + 1; k < j && k < n; k++) out.append(' ');
                if (j < n) out.append(c);
                i = j + 1;
            } else { out.append(c); i++; }
        }
        return out.toString();
    }

    static void calls(String body, Def def) {
        Matcher m = CALL.matcher(body);
        while (m.find()) {
            if (m.group(1) != null) def.indirect.add(m.group(2));
            else if (!KEYWORDS.contains(m.group(2))) def.direct.add(m.group(2));
        }
        m = POINTER_CALL.matcher(body);
        while (m.find()) def.indirect.add(m.group(1));
        def.indirect.removeAll(SAFE_INDIRECT);
    }

    static boolean ident(char c) { return Character.isLetterOrDigit(c) || c == '_'; }

    /** Function definitions (top-level `name(...) {`) and function-like macros. */
    static void parse(String file, String text, Map<String, Def> defs) {
        Matcher m = MACRO.matcher(text);
        while (m.find()) add(defs, m.group(1), file, m.start(), m.group(3), true);
        int depth = 0, i = 0, n = text.length();
        while (i < n) {
            char c = text.charAt(i);
            if (c == '#' && (i == 0 || text.charAt(i - 1) == '\n')) {   // skip preprocessor lines
                while (i < n && (text.charAt(i) != '\n' || text.charAt(i - 1) == '\\')) i++;
                continue;
            }
            if (c == '{') {
                if (depth == 0) {
                    int j = i - 1;
                    while (j >= 0 && Character.isWhitespace(text.charAt(j))) j--;
                    if (j >= 0 && text.charAt(j) == ')') {
                        int k = j, d = 0;
                        for (; k >= 0; k--) {
                            if (text.charAt(k) == ')') d++;
                            else if (text.charAt(k) == '(' && --d == 0) break;
                        }
                        k--;
                        while (k >= 0 && Character.isWhitespace(text.charAt(k))) k--;
                        int e = k + 1;
                        while (k >= 0 && ident(text.charAt(k))) k--;
                        String name = text.substring(k + 1, e);
                        int start = Math.max(text.lastIndexOf(';', k), text.lastIndexOf('}', k)) + 1;
                        int pre = text.lastIndexOf("\n#", k);   // a definition starts after preprocessor lines
                        if (pre >= start) start = text.indexOf('\n', pre + 1) + 1;
                        int end = i;
                        for (d = 0; end < n;) {
                            char x = text.charAt(end++);
                            if (x == '{') d++;
                            else if (x == '}' && --d == 0) break;
                        }
                        if (!name.isEmpty() && !KEYWORDS.contains(name)) add(defs, name, file, start, text.substring(i, end), false);
                        i = end;
                        continue;
                    }
                }
                depth++;
            } else if (c == '}') depth--;
            i++;
        }
    }

    static void add(Map<String, Def> defs, String name, String file, int start, String body, boolean macro) {
        Def def = defs.computeIfAbsent(name, k -> new Def());
        calls(body, def);
        def.where.add(new Site(file, start));
        def.macro |= macro;
    }

    public static int run(String[] args) {
        if (args.length < 1) { System.err.println("usage: CheckGc SRC_DIR [--fix]"); return 2; }
        String dir = args[0];
        boolean fix = args.length > 1 && args[1].equals("--fix");
        List<String> files = new ArrayList<>();
        for (String name : Host.list(dir)) if (name.endsWith(".c") || name.endsWith(".h")) files.add(name);
        Collections.sort(files);
        Map<String, Def> defs = new HashMap<>();
        Set<String> marked = new HashSet<>();
        Map<String, List<Site>> prototypes = new HashMap<>();
        for (String name : files) {
            String text = DECLSPEC.matcher(strip(read(dir + "/" + name))).replaceAll(m -> " ".repeat(m.group().length()));
            Matcher m = MARK.matcher(text);
            while (m.find()) marked.add(m.group(1));
            m = PROTOTYPE.matcher(text);
            while (m.find()) {   // prototypes start in column 0, without return or an assignment
                char first = text.charAt(m.start());
                if (Character.isWhitespace(first) || first == '#' || text.startsWith("return", m.start()) || KEYWORDS.contains(m.group(2))) continue;
                prototypes.computeIfAbsent(m.group(2), k -> new ArrayList<>()).add(new Site(name, m.start(1)));
            }
            parse(name, text, defs);
        }
        Set<String> gc = new HashSet<>();
        for (String seed : SEEDS) if (defs.containsKey(seed)) gc.add(seed);
        defs.forEach((name, def) -> { if (!def.indirect.isEmpty()) gc.add(name); });
        for (boolean changed = true; changed;) {
            changed = false;
            for (Map.Entry<String, Def> e : defs.entrySet())
                if (!gc.contains(e.getKey()) && !Collections.disjoint(e.getValue().direct, gc)) { gc.add(e.getKey()); changed = true; }
        }
        Set<String> internal = new HashSet<>(SEEDS); internal.add("jbv_collect");
        TreeSet<String> missing = new TreeSet<>(), extra = new TreeSet<>();
        for (String name : gc) if (!defs.get(name).macro && !marked.contains(name) && !internal.contains(name)) missing.add(name);
        for (String name : marked) if (defs.containsKey(name) && !gc.contains(name)) extra.add(name);
        for (String name : missing) {
            Def d = defs.get(name);
            TreeSet<String> hit = new TreeSet<>(d.direct); hit.retainAll(gc);
            String why = hit.isEmpty() ? "calls through " + String.join(", ", new TreeSet<>(d.indirect)) : "calls " + String.join(", ", hit);
            System.out.println("error: " + name + " (" + d.where.get(0).file() + ") may collect but is not marked JBV_GC: " + why);
        }
        for (String name : extra) System.out.println("warning: " + name + " is marked JBV_GC but never allocates or runs Java");
        if (fix && !missing.isEmpty()) {
            Map<String, TreeSet<Integer>> edits = new TreeMap<>();
            for (String name : missing)
                for (Site s : prototypes.getOrDefault(name, defs.get(name).where)) edits.computeIfAbsent(s.file(), k -> new TreeSet<>()).add(s.offset());
            for (Map.Entry<String, TreeSet<Integer>> e : edits.entrySet()) {
                StringBuilder text = new StringBuilder(read(dir + "/" + e.getKey()));
                for (int offset : e.getValue().descendingSet()) {
                    while (offset < text.length() && " \t\r\n".indexOf(text.charAt(offset)) >= 0) offset++;
                    text.insert(offset, "JBV_GC ");
                }
                Host.write(dir + "/" + e.getKey(), text.toString().getBytes(StandardCharsets.UTF_8));
            }
            System.out.println("marked " + missing.size() + " functions");
        }
        System.out.println(gc.size() + " GC-capable of " + defs.size() + " functions/macros; " + missing.size() + " unmarked, " + extra.size() + " over-marked");
        return !missing.isEmpty() && !fix ? 1 : 0;
    }

    static String read(String path) { return new String(Host.read(path), StandardCharsets.UTF_8); }
}
