package jbv.runtime;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Iterator;
/** Java implementations of built-in String members (see java_native in src/library.c):
 * instance members take the receiver first; constructors are static init(...). */
public final class Strings {
    private Strings() {}

    // ---- case ----
    public static String toLowerCase(String s) { return convert(s, false); }
    public static String toUpperCase(String s) { return convert(s, true); }
    /** Locales are accepted but casing is always Locale.ROOT (no Turkish/Lithuanian rules). */
    public static String toLowerCase(String s, java.util.Locale locale) { return convert(s, false); }
    public static String toUpperCase(String s, java.util.Locale locale) { return convert(s, true); }
    private static String convert(String s, boolean upper) {
        int n = s.length(), i = 0;
        // Fast path: unchanged ASCII prefix (non-ASCII may need SpecialCasing or context rules).
        for (; i < n; i++) { char c = s.charAt(i); if (c >= 0x80 || (upper ? c >= 'a' && c <= 'z' : c >= 'A' && c <= 'Z')) break; }
        if (i == n) return s;
        StringBuilder b = new StringBuilder(n + 8).append(s, 0, i);
        while (i < n) {
            int c = s.codePointAt(i), w = Character.charCount(c);
            String special = Unicode.special(c, upper);
            if (special != null) b.append(special);
            else if (!upper && c == 0x3a3) b.append(finalSigma(s, i) ? 'ς' : 'σ');
            else b.appendCodePoint(upper ? Character.toUpperCase(c) : Character.toLowerCase(c));
            i += w;
        }
        return b.toString();
    }
    /** Final sigma as the JDK decides it: within the word containing it (BreakIterator word
     * boundaries, approximated below) a cased letter precedes it and none follows. */
    private static boolean finalSigma(String s, int at) {
        for (int i = at; i > 0 && !boundary(s, i); i--)
            if (cased(s.charAt(i - 1))) {
                for (int j = at + 1; j < s.length() && !boundary(s, j); j++) if (cased(s.charAt(j))) return false;
                return true;
            }
        return false;
    }
    private static boolean cased(char c) { return Character.isUpperCase(c) || Character.isLowerCase(c) || Character.isTitleCase(c); }
    private static boolean ideograph(char c) { return c >= 0x4e00 && c <= 0x9fff || c >= 0xf900 && c <= 0xfaff; }
    private static boolean letter(char c) { int t = Character.getType(c); return Character.isLetter(c) && !ideograph(c) || c == '_' || t == Character.NON_SPACING_MARK || t == Character.ENCLOSING_MARK || t == Character.COMBINING_SPACING_MARK || t == Character.FORMAT || Character.isSurrogate(c); }
    private static boolean digit(char c) { return Character.getType(c) == Character.DECIMAL_DIGIT_NUMBER; }
    private static boolean midLetter(char c) { return c == '\'' || c == '.' || c == '-' || c == '’' || c == '·'; }
    private static boolean midDigit(char c) { return c == ',' || c == '.' || c == ';' || c == '\'' || c == '’'; }
    /** Approximates java.text.BreakIterator word boundaries for the final-sigma rule. */
    private static boolean boundary(String s, int i) {
        if (i <= 0 || i >= s.length()) return true;
        char a = s.charAt(i - 1), b = s.charAt(i);
        if (ideograph(a) || ideograph(b)) return true;
        if ((letter(a) || digit(a)) && (letter(b) || digit(b))) return false;
        char before = i >= 2 ? s.charAt(i - 2) : ' ', after = i + 1 < s.length() ? s.charAt(i + 1) : ' ';
        if (letter(b) && letter(before) && midLetter(a) || letter(a) && letter(after) && midLetter(b)) return false;
        return !(digit(b) && digit(before) && midDigit(a) || digit(a) && digit(after) && midDigit(b));
    }
    public static boolean equalsIgnoreCase(String s, String other) { return other == s || other != null && other.length() == s.length() && regionMatches(s, true, 0, other, 0, s.length()); }
    /** Mirrors the JDK: Latin-1 strings compare by char; two UTF-16 strings switch to code
     * points at a mismatching surrogate. */
    public static int compareToIgnoreCase(String s, String other) {
        int tlen = s.length(), olen = other.length();
        if (latin1(s) || latin1(other)) {
            for (int k = 0, n = Math.min(tlen, olen); k < n; k++) { int d = foldCompare(s.charAt(k), other.charAt(k)); if (d != 0) return d; }
            return tlen - olen;
        }
        for (int k1 = 0, k2 = 0; k1 < tlen && k2 < olen; k1++, k2++) {
            int cp1 = s.charAt(k1), cp2 = other.charAt(k2);
            if (cp1 == cp2 || foldCompare(cp1, cp2) == 0) continue;
            cp1 = codePointIncluding(s, cp1, k1, tlen); if (cp1 < 0) { k1++; cp1 = -cp1; }
            cp2 = codePointIncluding(other, cp2, k2, olen); if (cp2 < 0) { k2++; cp2 = -cp2; }
            int diff = foldCompare(cp1, cp2);
            if (diff != 0) return diff;
        }
        return tlen - olen;
    }
    private static boolean latin1(String s) { for (int i = 0; i < s.length(); i++) if (s.charAt(i) > 0xff) return false; return true; }
    private static int codePointIncluding(String s, int cp, int index, int end) {
        if (!Character.isSurrogate((char) cp)) return cp;
        if (Character.isLowSurrogate((char) cp)) { if (index > 0) { char c = s.charAt(index - 1); if (Character.isHighSurrogate(c)) return Character.toCodePoint(c, (char) cp); } }
        else if (index + 1 < end) { char c = s.charAt(index + 1); if (Character.isLowSurrogate(c)) return -Character.toCodePoint((char) cp, c); }
        return cp;
    }
    private static int foldCompare(int a, int b) {
        a = Character.toUpperCase(a); b = Character.toUpperCase(b);
        if (a != b) { a = Character.toLowerCase(a); b = Character.toLowerCase(b); if (a != b) return a - b; }
        return 0;
    }
    public static boolean regionMatches(String s, int at, String other, int from, int length) { return regionMatches(s, false, at, other, from, length); }
    public static boolean regionMatches(String s, boolean ignoreCase, int at, String other, int from, int length) {
        if (from < 0 || at < 0 || at > (long) s.length() - length || from > (long) other.length() - length) return false;
        if (!ignoreCase) { for (int i = 0; i < length; i++) if (s.charAt(at + i) != other.charAt(from + i)) return false; return true; }
        if (latin1(s) || latin1(other)) {
            for (int i = 0; i < length; i++) {
                char a = s.charAt(at + i), b = other.charAt(from + i);
                if (a == b) continue;
                char ua = Character.toUpperCase(a), ub = Character.toUpperCase(b);
                if (ua != ub && Character.toLowerCase(ua) != Character.toLowerCase(ub)) return false;
            }
            return true;
        }
        // Two UTF-16 strings: mirrors the JDK, which steps over surrogate pairs independently in each string.
        int last = at + length, olast = from + length;
        for (int t = at, o = from; t < last && o < olast; t++, o++) {
            int a = s.charAt(t), b = other.charAt(o);
            if (a == b) continue;
            a = codePointIncluding(s, a, t, last); if (a < 0) { t++; a = -a; }
            b = codePointIncluding(other, b, o, olast); if (b < 0) { o++; b = -b; }
            if (a == b) continue;
            int ua = Character.toUpperCase(a), ub = Character.toUpperCase(b);
            if (ua == ub || Character.toLowerCase(ua) == Character.toLowerCase(ub)) continue;
            return false;
        }
        return true;
    }

    // ---- regex-based ----
    public static String[] split(String s, String regex) { return split(s, regex, 0); }
    public static String[] split(String s, String regex, int limit) {
        // The JDK's fast path: one char that is not a regex metacharacter, or a backslash-escaped non-alphanumeric.
        char ch = 0;
        if (regex.length() == 1 && ".$|()[{^?*+\\".indexOf(regex.charAt(0)) < 0) ch = regex.charAt(0);
        else if (regex.length() == 2 && regex.charAt(0) == '\\' && !Character.isLetterOrDigit(regex.charAt(1)) && !Character.isSurrogate(regex.charAt(1))) ch = regex.charAt(1);
        if (ch == 0 || Character.isSurrogate(ch)) return java.util.regex.Pattern.compile(regex).split(s, limit);
        ArrayList<String> parts = new ArrayList<>();
        int start = 0, next;
        boolean limited = limit > 0;
        while ((next = s.indexOf(ch, start)) >= 0) {
            if (limited && parts.size() == limit - 1) break;
            parts.add(s.substring(start, next)); start = next + 1;
        }
        if (start == 0) return new String[]{s};
        parts.add(s.substring(start));
        int size = parts.size();
        if (limit == 0) while (size > 0 && parts.get(size - 1).isEmpty()) size--;
        String[] r = new String[size];
        for (int i = 0; i < size; i++) r[i] = parts.get(i);
        return r;
    }
    public static boolean matches(String s, String regex) { return java.util.regex.Pattern.matches(regex, s); }
    public static String replaceAll(String s, String regex, String replacement) { return java.util.regex.Pattern.compile(regex).matcher(s).replaceAll(replacement); }
    public static String replaceFirst(String s, String regex, String replacement) { return java.util.regex.Pattern.compile(regex).matcher(s).replaceFirst(replacement); }

    // ---- whitespace, code points, misc ----
    public static String strip(String s) { return stripTrailing(stripLeading(s)); }
    public static String stripLeading(String s) { int i = 0; while (i < s.length()) { int c = s.codePointAt(i); if (!Character.isWhitespace(c)) break; i += Character.charCount(c); } return s.substring(i); }
    public static String stripTrailing(String s) { int i = s.length(); while (i > 0) { int c = s.codePointBefore(i); if (!Character.isWhitespace(c)) break; i -= Character.charCount(c); } return s.substring(0, i); }
    public static java.util.stream.IntStream chars(String s) { int[] a = new int[s.length()]; for (int i = 0; i < a.length; i++) a[i] = s.charAt(i); return java.util.Arrays.stream(a); }
    public static java.util.stream.IntStream codePoints(String s) {
        int[] a = new int[s.codePointCount(0, s.length())]; for (int i = 0, j = 0; i < a.length; i++) { a[i] = s.codePointAt(j); j += Character.charCount(a[i]); }
        return java.util.Arrays.stream(a); }
    public static boolean isBlank(String s) { return stripLeading(s).isEmpty(); }
    public static int codePointAt(String s, int i) { if (i < 0 || i >= s.length()) throw new StringIndexOutOfBoundsException("Index " + i + " out of bounds for length " + s.length()); return Character.codePointAt(s, i); }
    public static int codePointBefore(String s, int i) { if (i < 1 || i > s.length()) throw new StringIndexOutOfBoundsException("Index " + i + " out of bounds for length " + s.length()); return Character.codePointBefore(s, i); }
    public static int codePointCount(String s, int from, int to) {
        if (from < 0 || to > s.length() || from > to) throw new IndexOutOfBoundsException();
        int n = to - from;
        for (int i = from; i < to - 1; i++) if (Character.isHighSurrogate(s.charAt(i)) && Character.isLowSurrogate(s.charAt(i + 1))) { n--; i++; }
        return n;
    }
    public static boolean contentEquals(String s, CharSequence other) {
        if (other.length() != s.length()) return false;
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) != other.charAt(i)) return false;
        return true;
    }
    public static String indent(String s, int n) {
        if (s.isEmpty()) return "";
        StringBuilder b = new StringBuilder();
        int i = 0, len = s.length();
        while (i < len) {
            int end = i; while (end < len && s.charAt(end) != '\n' && s.charAt(end) != '\r') end++;
            String line = s.substring(i, end);
            if (n > 0) b.append(" ".repeat(n)).append(line);
            else if (n < 0) { int k = 0; while (k < line.length() && k < -n && Character.isWhitespace(line.charAt(k))) k++; b.append(line, k, line.length()); }
            else b.append(line);
            b.append('\n');
            i = end < len && s.charAt(end) == '\r' && end + 1 < len && s.charAt(end + 1) == '\n' ? end + 2 : end + 1;
        }
        return b.toString();
    }
    public static String formatted(String s, Object[] args) { return Format.format(s, args); }
    public static String format(String format, Object[] args) { return Format.format(format, args); }
    public static String format(java.util.Locale locale, String format, Object[] args) { return Format.format(format, args); }
    public static String join(CharSequence delimiter, CharSequence[] elements) {
        java.util.Objects.requireNonNull(delimiter); StringBuilder b = new StringBuilder();
        for (int i = 0; i < elements.length; i++) { if (i > 0) b.append(delimiter); b.append(elements[i]); }
        return b.toString();
    }
    public static String join(CharSequence delimiter, Iterable<? extends CharSequence> elements) {
        java.util.Objects.requireNonNull(delimiter); StringBuilder b = new StringBuilder(); boolean first = true;
        for (Iterator<? extends CharSequence> it = elements.iterator(); it.hasNext(); first = false) { if (!first) b.append(delimiter); b.append(it.next()); }
        return b.toString();
    }
    public static String copyValueOf(char[] data) { return new String(data); }
    public static int indexOf(StringBuilder b, String str) { return b.toString().indexOf(str); }
    public static int indexOf(StringBuilder b, String str, int from) { return b.toString().indexOf(str, from); }
    public static int lastIndexOf(StringBuilder b, String str) { return b.toString().lastIndexOf(str); }
    public static int lastIndexOf(StringBuilder b, String str, int from) { return b.toString().lastIndexOf(str, from); }

    // ---- charsets: UTF-8, ISO-8859-1, US-ASCII, UTF-16(BE/LE); unmappable -> '?' / U+FFFD as in the JDK ----
    static final int UTF8 = 0, LATIN1 = 1, ASCII = 2, UTF16 = 3, UTF16BE = 4, UTF16LE = 5;
    public static byte[] getBytes(String s) { return encode(s, UTF8); }
    public static byte[] getBytes(String s, Charset charset) { return encode(s, Charsets.id(java.util.Objects.requireNonNull(charset))); }
    public static byte[] getBytes(String s, String name) throws java.io.UnsupportedEncodingException { return encode(s, Charsets.lookup(name)); }
    static byte[] encode(String s, int kind) {
        int n = s.length();
        if (kind >= UTF16) {   // lone surrogates become U+FFFD; UTF-16 writes a BOM unless empty
            int bom = kind == UTF16 && n > 0 ? 2 : 0; byte[] r = new byte[bom + 2 * n];
            if (bom > 0) { r[0] = (byte) 0xfe; r[1] = (byte) 0xff; }
            for (int i = 0; i < n; i++) {
                char c = s.charAt(i);
                if (Character.isHighSurrogate(c) && i + 1 < n && Character.isLowSurrogate(s.charAt(i + 1))) { put16(r, bom + 2 * i, c, kind); c = s.charAt(++i); }
                else if (Character.isSurrogate(c)) c = '�';
                put16(r, bom + 2 * i, c, kind);
            }
            return r;
        }
        if (kind != UTF8) {   // single-byte: unmappable chars and whole surrogate pairs become one '?'
            byte[] r = new byte[n]; int k = 0, max = kind == LATIN1 ? 0xff : 0x7f;
            for (int i = 0; i < n; i++) {
                char c = s.charAt(i);
                if (Character.isHighSurrogate(c) && i + 1 < n && Character.isLowSurrogate(s.charAt(i + 1))) i++;
                r[k++] = c <= max ? (byte) c : (byte) '?';
            }
            if (k == n) return r;
            byte[] out = new byte[k]; System.arraycopy(r, 0, out, 0, k); return out;
        }
        byte[] r = new byte[n * 3]; int k = 0;
        for (int i = 0; i < n; i++) {
            char c = s.charAt(i);
            if (c < 0x80) r[k++] = (byte) c;
            else if (c < 0x800) { r[k++] = (byte) (0xc0 | c >> 6); r[k++] = (byte) (0x80 | c & 0x3f); }
            else if (Character.isSurrogate(c)) {
                if (Character.isHighSurrogate(c) && i + 1 < n && Character.isLowSurrogate(s.charAt(i + 1))) {
                    int cp = Character.toCodePoint(c, s.charAt(++i));
                    r[k++] = (byte) (0xf0 | cp >> 18); r[k++] = (byte) (0x80 | cp >> 12 & 0x3f); r[k++] = (byte) (0x80 | cp >> 6 & 0x3f); r[k++] = (byte) (0x80 | cp & 0x3f);
                } else r[k++] = (byte) '?';
            } else { r[k++] = (byte) (0xe0 | c >> 12); r[k++] = (byte) (0x80 | c >> 6 & 0x3f); r[k++] = (byte) (0x80 | c & 0x3f); }
        }
        byte[] out = new byte[k]; System.arraycopy(r, 0, out, 0, k); return out;
    }
    private static void put16(byte[] r, int at, char c, int kind) { if (kind == UTF16LE) { r[at] = (byte) c; r[at + 1] = (byte) (c >> 8); } else { r[at] = (byte) (c >> 8); r[at + 1] = (byte) c; } }
    static String decode(byte[] b, int off, int len, int kind) {
        if (off < 0 || len < 0 || off > b.length - len) throw new StringIndexOutOfBoundsException("offset " + off + ", count " + len + ", length " + b.length);
        // Single-byte charsets and UTF-8 decode into a char[]: at most one char per byte.
        char[] r = new char[len];
        if (kind == LATIN1) { for (int i = 0; i < len; i++) r[i] = (char) (b[off + i] & 0xff); return new String(r); }
        if (kind == ASCII) { for (int i = Support.ascii(b, off, len, r); i < len; i++) { int c = b[off + i]; r[i] = c >= 0 ? (char) c : '�'; } return new String(r); }
        if (kind >= UTF16) {
            StringBuilder s = new StringBuilder(len / 2 + 1);
            int i = 0; boolean little = kind == UTF16LE;
            if (kind == UTF16 && len >= 2) { int m = (b[off] & 0xff) << 8 | b[off + 1] & 0xff; if (m == 0xfeff || m == 0xfffe) { little = m == 0xfffe; i = 2; } }
            char pending = 0;   // unpaired surrogates become U+FFFD, as in the JDK decoder
            for (; i + 1 < len; i += 2) {
                int x = b[off + i] & 0xff, y = b[off + i + 1] & 0xff; char c = (char) (little ? y << 8 | x : x << 8 | y);
                // A high surrogate and the unit after it form one malformed sequence unless that unit is a low surrogate.
                if (pending != 0) { if (Character.isLowSurrogate(c)) s.append(pending).append(c); else s.append('�'); pending = 0; continue; }
                if (Character.isHighSurrogate(c)) pending = c; else s.append(Character.isLowSurrogate(c) ? '�' : c);
            }
            if (pending != 0 || i < len) s.append('�');
            return s.toString();
        }
        // UTF-8 with the JDK decoder's replacement rules: each malformed sequence (as sized
        // by the JDK's malformedN) becomes one U+FFFD; an incomplete tail becomes one U+FFFD.
        int k = Support.ascii(b, off, len, r), i = off + k, end = off + len;   // bulk ASCII prefix
        while (i < end) {
            int c = b[i] & 0xff;
            if (c < 0x80) { r[k++] = (char) c; i++; continue; }
            int need = c >= 0xc2 && c <= 0xdf ? 1 : c >= 0xe0 && c <= 0xef ? 2 : c >= 0xf0 && c <= 0xf4 ? 3 : -1;
            if (need < 0) { r[k++] = '�'; i++; continue; }
            int have = Math.min(need, end - i - 1), b2 = have > 0 ? b[i + 1] & 0xff : 0, b3 = have > 1 ? b[i + 2] & 0xff : 0, b4 = have > 2 ? b[i + 3] & 0xff : 0;
            boolean c2 = (b2 & 0xc0) == 0x80, c3 = (b3 & 0xc0) == 0x80, c4 = (b4 & 0xc0) == 0x80;
            int bad;   // length of a malformed sequence, 0 if well-formed, -1 if an incomplete tail
            if (need == 1) bad = have < 1 ? -1 : c2 ? 0 : 1;
            else if (need == 2) {
                boolean head = c == 0xe0 && (b2 & 0xe0) == 0x80 || !c2;
                if (have < 2) bad = have < 1 || !head ? -1 : 1;
                else if (head) bad = 1; else if (!c3) bad = 2;
                else { int cp = (c & 0x0f) << 12 | (b2 & 0x3f) << 6 | b3 & 0x3f; bad = Character.isSurrogate((char) cp) ? 3 : 0; }
            } else {
                boolean head = c == 0xf0 && (b2 < 0x90 || b2 > 0xbf) || c == 0xf4 && (b2 & 0xf0) != 0x80 || !c2;
                if (have < 3) bad = have < 1 ? -1 : head ? 1 : have < 2 ? -1 : !c3 ? 2 : -1;
                else {
                    int cp = (c & 0x07) << 18 | (b2 & 0x3f) << 12 | (b3 & 0x3f) << 6 | b4 & 0x3f;
                    if (c2 && c3 && c4 && cp >= 0x10000 && cp <= 0x10ffff) bad = 0;
                    else bad = c > 0xf4 || head ? 1 : !c3 ? 2 : 3;
                }
            }
            if (bad < 0) { r[k++] = '�'; break; }
            if (bad > 0) { r[k++] = '�'; i += bad; continue; }
            int cp = need == 1 ? (c & 0x1f) << 6 | b2 & 0x3f : need == 2 ? (c & 0x0f) << 12 | (b2 & 0x3f) << 6 | b3 & 0x3f
                : (c & 0x07) << 18 | (b2 & 0x3f) << 12 | (b3 & 0x3f) << 6 | b4 & 0x3f;
            if (cp >= 0x10000) { r[k++] = Character.highSurrogate(cp); r[k++] = Character.lowSurrogate(cp); } else r[k++] = (char) cp;
            i += need + 1;
        }
        return new String(r, 0, k);
    }
    public static String init(byte[] b) { return decode(b, 0, b.length, UTF8); }
    public static String init(byte[] b, int off, int len) { return decode(b, off, len, UTF8); }
    public static String init(byte[] b, String name) throws java.io.UnsupportedEncodingException { return decode(b, 0, b.length, Charsets.lookup(name)); }
    public static String init(byte[] b, Charset charset) { return decode(b, 0, b.length, Charsets.id(java.util.Objects.requireNonNull(charset))); }
    public static String init(byte[] b, int off, int len, Charset charset) { return decode(b, off, len, Charsets.id(java.util.Objects.requireNonNull(charset))); }
    public static String init(StringBuilder b) { return b.toString(); }
    public static String init(int[] codePoints, int off, int count) {
        if (off < 0 || count < 0 || off > codePoints.length - count) throw new StringIndexOutOfBoundsException();
        StringBuilder b = new StringBuilder(count);
        for (int i = off; i < off + count; i++) b.appendCodePoint(codePoints[i]);
        return b.toString();
    }

    /** The supported charsets; java.nio.charset.Charset instances are created here. */
    public static final class Charsets {
        private Charsets() {}
        public static final String[][] NAMES = {
            {"UTF-8", "UTF8", "unicode-1-1-utf-8"}, {"ISO-8859-1", "ISO8859_1", "latin1", "l1", "ISO_8859-1", "8859_1", "cp819", "IBM819", "ISO8859-1"},
            {"US-ASCII", "ASCII", "us", "ISO646-US", "cp367", "ascii7", "646", "iso_646.irv:1983", "ANSI_X3.4-1968", "default"},
            {"UTF-16", "UTF_16", "utf16", "unicode", "UnicodeBig"}, {"UTF-16BE", "UTF_16BE", "X-UTF-16BE", "UnicodeBigUnmarked", "ISO-10646-UCS-2"},
            {"UTF-16LE", "UTF_16LE", "X-UTF-16LE", "UnicodeLittleUnmarked"}};
        public static int find(String name) {
            for (int i = 0; i < NAMES.length; i++) for (String alias : NAMES[i]) if (equalsIgnoreCase(alias, name)) return i;
            return -1;
        }
        static int lookup(String name) throws java.io.UnsupportedEncodingException {
            int id = find(java.util.Objects.requireNonNull(name, "charsetName"));
            if (id < 0) throw new java.io.UnsupportedEncodingException(name);
            return id;
        }
        static int id(Charset charset) { int id = find(charset.name()); if (id < 0) throw new UnsupportedOperationException(charset.name()); return id; }
    }
}
