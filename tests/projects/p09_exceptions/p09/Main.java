package p09;
import java.util.*;
public final class Main {
    static final class ModException extends Exception { final int code; ModException(String m, int code, Throwable cause) { super(m, cause); this.code = code; } }
    static final class Resource implements AutoCloseable {
        static final List<String> log = new ArrayList<>(); final String name; final boolean failClose;
        Resource(String name, boolean failClose) { this.name = name; this.failClose = failClose; log.add("open " + name); }
        public void close() { log.add("close " + name); if (failClose) throw new IllegalStateException("close " + name); }
    }
    static int depth(int n) { return n == 0 ? Integer.parseInt("x") : depth(n - 1) + 1; }
    static String trace() {
        StringBuilder s = new StringBuilder();
        try (Resource a = new Resource("a", false); Resource b = new Resource("b", true)) {
            s.append("body;"); throw new UnsupportedOperationException("body");
        } catch (UnsupportedOperationException e) {
            s.append(e.getMessage()).append(" suppressed=").append(e.getSuppressed().length).append(':').append(e.getSuppressed()[0].getMessage());
        } finally { s.append(";finally"); }
        return s.toString();
    }
    @SuppressWarnings("finally") static int finallyWins() { int x = 1; try { return x; } finally { x = 2; } }
    public static String run() {
        StringBuilder s = new StringBuilder(trace()).append(' ').append(Resource.log).append(' ');
        try { depth(5); } catch (NumberFormatException e) { s.append("nfe:").append(e.getMessage()).append(' '); }
        try {
            try { Object o = "s"; Integer i = (Integer) o; s.append(i); }
            catch (ClassCastException | ArithmeticException e) { throw new ModException("wrapped", 7, e); }
        } catch (ModException e) { s.append(e.getMessage()).append(e.code).append(e.getCause() instanceof ClassCastException).append(' '); }
        int[] a = new int[2];
        try { a[2] = 1; } catch (ArrayIndexOutOfBoundsException e) { s.append("aioobe "); }
        try { Object n = null; n.hashCode(); } catch (NullPointerException e) { s.append("npe "); }
        try { s.append(10 / (a.length - 2)); } catch (ArithmeticException e) { s.append(e.getMessage()).append(' '); }
        try { throw new Error("custom"); } catch (Throwable t) { s.append(t).append(' '); }
        s.append(finallyWins());
        return s.toString();
    }
}
