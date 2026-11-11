package p08;
public final class Main {
    static String classify(Object o) {
        if (o instanceof Integer i && i > 10) return "big" + i;
        if (o instanceof String s && !s.isEmpty()) return "str" + s.length();
        if (o instanceof int[] a) return "ints" + a.length;
        return "other";
    }
    static int days(int month) {
        return switch (month) { case 2 -> 28; case 4, 6, 9, 11 -> 30; default -> { int d = 31; yield d; } };
    }
    static String level(String s) {
        return switch (s) { case "low", "l" -> "1"; case "high" -> "3"; default -> "2"; };
    }
    public static String run() {
        StringBuilder s = new StringBuilder();
        for (Object o : new Object[]{42, 5, "abc", "", new int[3], 2.5}) s.append(classify(o)).append(' ');
        for (int m = 1; m <= 12; m++) s.append(days(m)).append(',');
        var text = """
            line one
              line two\
             joined
            """;
        return s + level("l") + level("high") + level("?") + " " + text.replace('\n', '/');
    }
}
