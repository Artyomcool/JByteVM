package p17;
public final class Main {
    static String caesar(String s, int k) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= 'a' && c <= 'z') c = (char) ('a' + (c - 'a' + k) % 26);
            else if (c >= 'A' && c <= 'Z') c = (char) ('A' + (c - 'A' + k) % 26);
            b.append(c);
        }
        return b.toString();
    }
    static String wrap(String text, int width) {
        StringBuilder out = new StringBuilder(); int col = 0;
        for (String word : words(text)) {
            if (col > 0 && col + 1 + word.length() > width) { out.append('\n'); col = 0; }
            else if (col > 0) { out.append(' '); col++; }
            out.append(word); col += word.length();
        }
        return out.toString();
    }
    static java.util.List<String> words(String text) {
        java.util.List<String> r = new java.util.ArrayList<>(); int start = -1;
        for (int i = 0; i <= text.length(); i++) {
            boolean space = i == text.length() || text.charAt(i) == ' ';
            if (!space && start < 0) start = i;
            if (space && start >= 0) { r.add(text.substring(start, i)); start = -1; }
        }
        return r;
    }
    public static String run() {
        String msg = "The quick brown Fox jumps over the lazy dog";
        String enc = caesar(msg, 13);
        return enc + " | " + caesar(enc, 13).equals(msg) + " | " + wrap(msg, 12).replace("\n", "/") + " | " + msg.hashCode() + " " + "".hashCode()
            + " " + msg.indexOf("lazy") + " " + msg.contains("Fox") + " " + msg.replace("o", "0") + " " + String.valueOf(new char[]{'o', 'k'}) + " " + "\u00e9\u4e2d".length();
    }
}
