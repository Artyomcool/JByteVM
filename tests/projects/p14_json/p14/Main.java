package p14;
import java.util.*;
public final class Main {
    static final class Parser {
        final String s; int i;
        Parser(String s) { this.s = s; }
        void ws() { while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++; }
        Object value() {
            ws(); char c = s.charAt(i);
            if (c == '{') { i++; Map<String, Object> m = new LinkedHashMap<>(); ws(); if (s.charAt(i) == '}') { i++; return m; }
                while (true) { ws(); String k = (String) value(); ws(); i++; m.put(k, value()); ws(); if (s.charAt(i++) == '}') return m; } }
            if (c == '[') { i++; List<Object> l = new ArrayList<>(); ws(); if (s.charAt(i) == ']') { i++; return l; }
                while (true) { l.add(value()); ws(); if (s.charAt(i++) == ']') return l; } }
            if (c == '"') { StringBuilder b = new StringBuilder(); i++;
                while (s.charAt(i) != '"') { char ch = s.charAt(i++); if (ch == '\\') { char e = s.charAt(i++); ch = e == 'n' ? '\n' : e == 'u' ? (char) Integer.parseInt(s.substring(i, i += 4), 16) : e; } b.append(ch); }
                i++; return b.toString(); }
            if (s.startsWith("true", i)) { i += 4; return true; }
            if (s.startsWith("false", i)) { i += 5; return false; }
            if (s.startsWith("null", i)) { i += 4; return null; }
            int start = i; while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
            String num = s.substring(start, i);
            return num.contains(".") || num.contains("e") || num.contains("E") ? (Object) Double.parseDouble(num) : (Object) Long.parseLong(num);
        }
    }
    static String dump(Object o) {
        if (o instanceof Map<?, ?> m) { StringBuilder b = new StringBuilder("{"); for (Map.Entry<?, ?> e : m.entrySet()) b.append(e.getKey()).append(':').append(dump(e.getValue())).append(','); return b.append('}').toString(); }
        if (o instanceof List<?> l) { StringBuilder b = new StringBuilder("["); for (Object x : l) b.append(dump(x)).append(','); return b.append(']').toString(); }
        return String.valueOf(o);
    }
    public static String run() {
        String json = "{ \"name\": \"Mod \\u0041\\n\", \"version\": 3, \"weight\": -1.5e2, \"tags\": [\"a\", \"b\", []], \"nested\": {\"ok\": true, \"none\": null}, \"big\": 123456789012 }";
        Object v = new Parser(json).value();
        @SuppressWarnings("unchecked") Map<String, Object> m = (Map<String, Object>) v;
        return dump(v) + " " + m.keySet() + " " + ((Number) m.get("big")).longValue() * 2;
    }
}
