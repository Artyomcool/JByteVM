package p22;
import java.util.*;
public final class Main {
    static final List<String> order = new ArrayList<>();
    static final class A { static final int X; static { order.add("A"); X = B.Y + 1; } }
    static final class B { static final int Y; static { order.add("B"); Y = 41; } }
    static final class Lazy { static { order.add("Lazy"); } static final Lazy INSTANCE = new Lazy(); int hits; }
    interface Constants { int K = 7; String NAME = "const"; }
    static final class Broken { static int value = compute(); static int compute() { throw new IllegalStateException("boom"); } }
    static final class Counter { static int created; final int id; Counter() { id = ++created; } }
    public static String run() {
        order.add("run");
        int x = A.X;
        Lazy.INSTANCE.hits++; Lazy.INSTANCE.hits++;
        StringBuilder s = new StringBuilder();
        s.append(x).append(' ').append(order).append(' ').append(Lazy.INSTANCE.hits).append(' ').append(Constants.K).append(Constants.NAME).append(' ');
        try { int v = Broken.value; s.append(v); } catch (ExceptionInInitializerError e) { s.append("eiie:").append(e.getCause().getMessage()); }
        try { int v = Broken.value; s.append(v); } catch (NoClassDefFoundError e) { s.append(" ncdfe"); }
        for (int i = 0; i < 3; i++) new Counter();
        return s.append(' ').append(Counter.created).toString();
    }
}
