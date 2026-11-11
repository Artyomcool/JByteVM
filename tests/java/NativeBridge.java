public class NativeBridge {
    interface Op { int apply(int n); }
    static class Base implements Op {
        int value;
        long wide;
        double real;
        Object link;
        Base peer;
        static int shared;
        Base(int n) { value = n; }
        public int apply(int n) { return value + n; }
        native int nativeInstance(int n);
        private int secret(int n) { return value - n; }
    }
    static class Child extends Base {
        Child(int n) { super(n); }
        public int apply(int n) { return value + n + 100; }
        public int secret(int n) { return -999; }
    }
    static class Other {}
    static class Init {
        static Object slot;
        static int ready = checkpoint();
    }
    static native int checkpoint();
    static native int nativeCall(Base b, int n);
    static native void throwNative(int n);
    static native Base nativeFactory(int n);
    static native int again(int n);
    public static int recurse(int n) { return n == 0 ? 7 : again(n - 1); }
    public static Base make(int n) { return new Child(n); }
    public static Base identity(Base b) { return b; }
    public static int callNative(Base b, int n) { return nativeCall(b, n); }
    public static int caught(int n) {
        try { throwNative(n); return -1; }
        catch (IllegalArgumentException e) { return 42; }
    }
    public static int explode(int n) { throw new IllegalStateException(); }
    public static Base factory(int n) { return nativeFactory(n); }
    public static long fields(Base b) { return b.value + b.wide + (long)b.real; }
    public static int elements(int[] a) { return a[0] + a[1] + a[2]; }
}
