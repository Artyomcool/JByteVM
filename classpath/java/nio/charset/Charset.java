package java.nio.charset;
/** Named charsets supported by the runtime: UTF-8, ISO-8859-1, US-ASCII, UTF-16, UTF-16BE, UTF-16LE.
 * Encoding/decoding goes through String (getBytes, new String(bytes, charset)). */
public abstract class Charset implements Comparable<Charset> {
    private final String name; private final String[] aliases;
    protected Charset(String canonicalName, String[] aliases) { this.name = canonicalName; this.aliases = aliases == null ? new String[0] : aliases; }
    private static final class Named extends Charset { Named(String[] names) { super(names[0], names); } }
    private static Charset[] all;
    static Charset of(int id) {
        if (all == null) { String[][] n = jbv.runtime.Strings.Charsets.NAMES; all = new Charset[n.length]; for (int i = 0; i < n.length; i++) all[i] = new Named(n[i]); }
        return all[id];
    }
    public static Charset forName(String name) {
        if (name == null) throw new IllegalArgumentException("Null charset name");
        int id = jbv.runtime.Strings.Charsets.find(name);
        if (id < 0) throw new UnsupportedCharsetException(name);
        return of(id);
    }
    public static Charset forName(String name, Charset fallback) { try { return forName(name); } catch (IllegalArgumentException e) { return fallback; } }
    public static boolean isSupported(String name) { return jbv.runtime.Strings.Charsets.find(name) >= 0; }
    public static Charset defaultCharset() { return of(0); }
    public final String name() { return name; }
    public String displayName() { return name; }
    public final java.util.Set<String> aliases() { java.util.HashSet<String> s = new java.util.HashSet<>(); for (int i = 1; i < aliases.length; i++) s.add(aliases[i]); return java.util.Collections.unmodifiableSet(s); }
    public boolean canEncode() { return true; }
    public final int compareTo(Charset other) { return jbv.runtime.Strings.compareToIgnoreCase(name, other.name); }
    public final boolean equals(Object o) { return o instanceof Charset c && name.equals(c.name); }
    public final int hashCode() { return name.hashCode(); }
    public final String toString() { return name; }
}
