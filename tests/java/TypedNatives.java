public class TypedNatives {
    public static native boolean invert(boolean x);
    public static native byte byteValue(byte x);
    public static native char charValue(char x);
    public static native short shortValue(short x);
    public static native int add(int x, int y);
    public static native long add(long x, long y);
    public static native float floatValue(float x);
    public static native double doubleValue(double x);
    public static native Object identity(Object x);
    public static native int[] array(int[] x);
    public static native int context();
    public static native void nothing();
    public static native long mixed(int i, long j, float f, double d, Object ref, byte b, char c, short s, boolean z);
    public static native void throwIt(Throwable t);
    public static native void fail(int status);
    public static native int outer(boolean recover);
    public static native int again(int n);
    public static native Object badReference();
    public static native float specialFloat(int which);
    public static native double specialDouble(int which);
    public static native int rebind();
    public static native int invokeConvenience();
    public native int instance();
    public static int ordinary(int n) { return n + 1; }
    public static int recurse(int n) { return n == 0 ? 7 : again(n - 1); }
    public static int caught() {
        try { throwIt(new IllegalArgumentException()); return -1; }
        catch (IllegalArgumentException e) { return 42; }
    }
    public static int caughtStatus() {
        try { fail(9); return -1; }
        catch (ArithmeticException e) { return 43; }
    }
    public static long javaMixed(long j, double d, float f, int[] a, Object o, byte b, char c, short s, boolean z) {
        return j + (long)d + (long)f + a[0] + (o == null ? 0 : 100) + b + c + s + (z ? 1 : 0);
    }
    public static float javaFloat(float f) { return f + 0.25f; }
    public static double javaDouble(double d) { return d + 0.5; }
    public static Object javaReference(Object o) { return o; }
    public static void javaVoid() {}
    public static int nativeLoop(int n) {
        int sum = 0;
        for (int i = 0; i < n; i++) sum += add(i, 7);
        return sum;
    }
}
class TypedInner {
    public static native int context();
    public static native void fail(int status);
}
