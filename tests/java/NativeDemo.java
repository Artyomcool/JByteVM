public class NativeDemo {
    static native long bridge(long value, double scale, int n);
    static native long leaf(long value, double scale, int n);
    public static long callback(long value, double scale, int n) {
        return leaf(value, scale, n) + 1;
    }
    public static long entry(int n) {
        return bridge(0x1234000000000000L + n, 2.5, n);
    }
}
