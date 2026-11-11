package p01;
public final class Main {
    static String greet(String who, int times) {
        StringBuilder s = new StringBuilder();
        for (int i = 0; i < times; i++) s.append(i == 0 ? "" : ", ").append("hello ").append(who).append('#').append(i);
        return s.toString();
    }
    static String kind(String command) {
        switch (command) {
            case "spawn": return "S";
            case "despawn": return "D";
            case "tick": return "T";
            default: return "?";
        }
    }
    public static String run() {
        String r = greet("world", 3) + " | " + kind("spawn") + kind("tick") + kind("nope");
        r += " | " + "Mod".concat("Loader").substring(3, 9) + " " + "abc".compareTo("abd") + " " + "x".repeat(3);
        r += " | " + 'a' + 1 + " " + (char) ('a' + 1) + " " + 7 / 2 + " " + 7 % -3 + " " + -7 / 2.0 + " " + 1e20f + " " + 0.1 + 0.2;
        r += " | " + Integer.MAX_VALUE + 1 + " " + (Integer.MAX_VALUE + 1) + " " + Long.MIN_VALUE + " " + (byte) 200 + " " + (short) 70000;
        return r;
    }
}
