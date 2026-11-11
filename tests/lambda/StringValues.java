import java.nio.charset.*;
import java.util.*;
/** String/Character/Charset/Class-name scenarios hashed for HotSpot comparison. */
public class StringValues {
    static int h;
    static void mix(int v) { h = h * 31 + v; }
    static void mix(String s) { mix(s == null ? -7 : s.hashCode()); }
    static void mix(boolean b) { mix(b ? 1 : 0); }
    static void mix(byte[] b) { mix(Arrays.hashCode(b)); }
    static void mix(String[] a) { mix(a.length); for (String s : a) mix(s); }
    static void fail(Runnable r) { try { r.run(); mix(0); } catch (RuntimeException e) { mix(e.getClass().getName()); } }
    static final String[] SAMPLES = {"", "Hello World", "ÀÉÎõü ßtraße", "ΟΔΥΣΣΕΥΣ ΣΑΣ Σ", "Привет, Мир! ЁЖ", "İstanbul ıi", "ǅungla ǈ ǋ", "ﬁne ŉ ǰ",
        "日本語テキスト", "😀 emoji 𝔸𝔹", "tab\tnew\nline\r\n", "    padded 　 ", "MiXeD123_case", "İıΣς", "a\ud800b", "x"};

    public static int cases(int seed) {
        h = seed;
        for (String s : SAMPLES) {
            mix(s.toUpperCase()); mix(s.toLowerCase()); mix(s.strip()); mix(s.stripLeading()); mix(s.stripTrailing()); mix(s.isBlank()); mix(s.trim());
            for (String t : SAMPLES) { mix(s.equalsIgnoreCase(t)); mix(Integer.signum(s.compareToIgnoreCase(t))); }
            mix(s.equalsIgnoreCase(s.toUpperCase())); mix(s.regionMatches(true, 1, s.toUpperCase(), 1, Math.max(0, s.length() - 2)));
            mix(s.codePointCount(0, s.length())); if (!s.isEmpty()) { mix(s.codePointAt(0)); mix(s.codePointBefore(s.length())); }
            mix(s.contentEquals(new StringBuilder(s))); mix(s.indent(2)); mix(s.indent(-1)); mix(s.indent(0));
        }
        fail(() -> "abc".codePointAt(5)); fail(() -> "abc".codePointBefore(0));
        return h;
    }

    public static int splitJoin(int seed) {
        h = seed;
        String[] inputs = {"a,b,,c,,", ",a,b", "", "a", ",", ",,,", "one two  three", "k=v;x=y;", "a|b|c", "path/to/file.txt", "1.2.3"};
        String[] seps = {",", " ", ";", "=", "\\|", "\\.", "/", "x"};
        for (String in : inputs) for (String sep : seps) for (int limit : new int[]{0, -1, 1, 2, 5}) mix(in.split(sep, limit));
        for (String in : inputs) mix(in.split(","));
        mix(String.join("-", "a", "b", "c")); mix(String.join(", ", List.of("x", "y"))); mix(String.join("", new ArrayList<String>()));
        mix(String.join("/", new StringBuilder("sb"), "s")); mix(String.copyValueOf(new char[]{'o', 'k'}));
        fail(() -> String.join(null, "a"));
        return h;
    }

    public static int charsets(int seed) {
        h = seed;
        Charset[] sets = {StandardCharsets.UTF_8, StandardCharsets.ISO_8859_1, StandardCharsets.US_ASCII, StandardCharsets.UTF_16, StandardCharsets.UTF_16BE, StandardCharsets.UTF_16LE};
        for (String s : SAMPLES) {
            mix(s.getBytes());
            for (Charset c : sets) { byte[] b = s.getBytes(c); mix(b); mix(new String(b, c)); mix(new String(b, 0, b.length / 2, c)); }
        }
        byte[][] raw = {{(byte) 0xc3, (byte) 0xa9}, {(byte) 0xc3}, {(byte) 0xe2, (byte) 0x82}, {(byte) 0xe2, (byte) 0x82, (byte) 0xac, 'x'}, {(byte) 0xf0, (byte) 0x9f, (byte) 0x98, (byte) 0x80},
            {(byte) 0xed, (byte) 0xa0, (byte) 0x80}, {(byte) 0xc0, (byte) 0x80}, {(byte) 0xff, 'a', (byte) 0x80}, {(byte) 0xf4, (byte) 0x90, (byte) 0x80, (byte) 0x80}, {'a', (byte) 0xe0, (byte) 0xa0}};
        for (byte[] b : raw) { mix(new String(b, StandardCharsets.UTF_8)); mix(new String(b)); mix(new String(b, StandardCharsets.US_ASCII)); mix(new String(b, StandardCharsets.UTF_16)); }
        for (String name : new String[]{"utf-8", "UTF8", "latin1", "US-ASCII", "utf-16le"}) {
            Charset c = Charset.forName(name); mix(c.name()); mix(c.toString()); mix(c.equals(Charset.forName(c.name()))); mix(Charset.isSupported(name));
            try { mix("héllo".getBytes(name)); mix(new String("héllo".getBytes(name), name)); } catch (java.io.UnsupportedEncodingException e) { mix(-1); }
        }
        mix(Charset.isSupported("x-unknown")); mix(Charset.defaultCharset().name());
        fail(() -> Charset.forName("x-unknown"));
        try { "a".getBytes("x-unknown"); } catch (java.io.UnsupportedEncodingException e) { mix(e.getMessage()); }
        mix(new String(new int[]{0x48, 0x1F600, 0x49}, 0, 3)); mix(new String(new StringBuilder("built")));
        fail(() -> new String(new byte[2], 1, 5, StandardCharsets.UTF_8));
        return h;
    }

    public static int characters(int seed) {
        h = seed;
        Random r = new Random(seed);
        for (int i = 0; i < 4000; i++) {
            int c = i < 1200 ? i * 3 : r.nextInt(0x110000);
            mix(Character.getType(c)); mix(Character.isLetter(c)); mix(Character.isLetterOrDigit(c)); mix(Character.isDigit(c)); mix(Character.isUpperCase(c)); mix(Character.isLowerCase(c));
            mix(Character.isTitleCase(c)); mix(Character.isAlphabetic(c)); mix(Character.isSpaceChar(c)); mix(Character.isWhitespace(c)); mix(Character.isISOControl(c)); mix(Character.isDefined(c));
            mix(Character.isJavaIdentifierStart(c)); mix(Character.isJavaIdentifierPart(c)); mix(Character.isIdentifierIgnorable(c));
            mix(Character.toUpperCase(c)); mix(Character.toLowerCase(c)); mix(Character.toTitleCase(c)); mix(Character.getNumericValue(c));
            if (c < 0x10000) { char ch = (char) c; mix(Character.toUpperCase(ch)); mix(Character.isLetter(ch)); mix(Character.getNumericValue(ch)); }
        }
        mix(Character.getType(-1)); mix(Character.toUpperCase(0x110000));
        return h;
    }

    enum Color { RED, GREEN }
    interface Shape {}
    static class Outer { class Inner {} static class Nested { class Deep {} } }
    public static int classNames(int seed) {
        h = seed;
        Object anon = new Object() {};
        class Local {}
        Class<?>[] types = {String.class, int.class, int[][].class, Outer.Inner.class, Outer.Nested.Deep.class, Outer.Nested[].class, Local.class, anon.getClass(),
            Color.class, Shape.class, Map.Entry.class, StringValues.class, Integer.class};
        for (Class<?> c : types) {
            mix(c.getSimpleName()); mix(c.getPackageName()); mix(c.getCanonicalName()); mix(c.isMemberClass()); mix(c.isAnonymousClass()); mix(c.isRecord());
            mix(c.getDeclaringClass() == null ? "-" : c.getDeclaringClass().getName()); mix(c.getEnclosingClass() == null ? "-" : c.getEnclosingClass().getName());
            mix(c.getNestHost().getName());
        }
        mix(Arrays.toString(Color.class.getEnumConstants())); mix(String.valueOf(String.class.getEnumConstants()));
        return h;
    }
}
