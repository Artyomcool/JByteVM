public class Exceptions {
    public static class Mine extends RuntimeException {}
    static int marker;
    static native int gc();
    static int divide(int n) { return 100 / n; }
    public static int nested(int n) {
        try { return divide(n); }
        catch (ArithmeticException e) { return 17; }
    }
    public static int ordered(int n) {
        try {
            if (n == 0) throw new Mine();
            if (n == 1) throw null;
            return (new int[1])[n];
        } catch (Mine e) { return 1; }
        catch (NullPointerException e) { return 2; }
        catch (RuntimeException e) { return 3; }
    }
    static void throwing(int n) {
        try { if (n == 0) throw new Mine(); }
        finally { marker += 4; }
    }
    public static int cleanup(int n) {
        marker = 0;
        try { throwing(n); }
        catch (Mine e) { marker += 8; }
        finally { marker += 16; }
        return marker;
    }
    public static int suppressed(int n) {
        RuntimeException a = new RuntimeException();
        RuntimeException b = new RuntimeException();
        a.initCause(b);
        a.addSuppressed(b);
        Throwable[] snapshot = a.getSuppressed();
        snapshot[0] = null;
        try { a.addSuppressed(a); }
        catch (IllegalArgumentException expected) { n += 10; }
        return n + (a.getCause() == b ? 1 : 0) + (a.getSuppressed()[0] == b ? 2 : 0);
    }
    public static int gcCatch(int n) {
        try { throw new Mine(); }
        catch (Throwable e) { gc(); return e instanceof Mine ? n + 1 : 0; }
    }
    public static int uncaught() { throw new Mine(); }
    static class BadInit { static int VALUE = divide(0); }
    public static int initialization(int n) {
        try { return BadInit.VALUE; }
        catch (ExceptionInInitializerError e) { return e.getCause() instanceof ArithmeticException ? 11 : 12; }
        catch (NoClassDefFoundError e) { return 21; }
    }
    static class Resource implements AutoCloseable {
        public void close() { marker++; throw new Mine(); }
    }
    public static int resources(int n) {
        marker = 0;
        try (Resource first = new Resource(); Resource second = new Resource()) { throw new Mine(); }
        catch (Mine e) { return n + marker + e.getSuppressed().length * 10; }
    }
}
