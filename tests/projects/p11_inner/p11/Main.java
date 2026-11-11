package p11;
import java.util.*;
public final class Main {
    private int counter = 10;
    private static String secret() { return "s"; }
    final class Ticker { int tick() { return ++counter; } }
    static final class Pair { final int a, b; Pair(int a, int b) { this.a = a; this.b = b; } }
    interface Op { int apply(int x); }
    Op adder(int k) {
        class Local implements Op { public int apply(int x) { return x + k + counter; } }
        return new Local();
    }
    public static String run() {
        Main m = new Main();
        Main.Ticker t = m.new Ticker();
        t.tick(); t.tick();
        Op twice = new Op() { int calls; public int apply(int x) { calls++; return x * 2 + calls; } };
        Iterator<Integer> countdown = new Iterator<>() { int n = 3; public boolean hasNext() { return n > 0; } public Integer next() { return n--; } };
        StringBuilder s = new StringBuilder();
        while (countdown.hasNext()) s.append(countdown.next());
        return m.counter + " " + m.adder(5).apply(1) + " " + twice.apply(3) + twice.apply(3) + " " + new Pair(1, 2).b + " " + s + secret()
            + " " + Ticker.class.getName() + " " + twice.getClass().getName();
    }
}
