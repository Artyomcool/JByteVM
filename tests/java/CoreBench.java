/* Small repeatable workloads for comparing interpreter implementations. */
public class CoreBench {
    interface Step { int apply(int x); }
    static class Add implements Step {
        int delta = 3;
        public int apply(int x) { return x + delta; }
    }
    public static int integers(int n) {
        int x = 1;
        for (int i = 0; i < n; ++i) x = (x * 33 + i) ^ (x >>> 7);
        return x;
    }
    public static int arrays(int n) {
        int[] data = new int[64];
        int x = 0;
        for (int i = 0; i < n; ++i) {
            int at = i & 63;
            data[at] = data[at] * 17 + i;
            x ^= data[at];
        }
        return x;
    }
    public static int wide(int n) {
        long x = 0x123456789abcdefL;
        double d = 0.25;
        for (int i = 0; i < n; ++i) {
            x = (x * 17 + i) ^ (x >>> 13);
            d = d * 0.5 + i;
        }
        return (int)(x ^ (long)d);
    }
    public static int calls(int n) {
        Step step = new Add();
        int x = 0;
        for (int i = 0; i < n; ++i) x = step.apply(x);
        return x;
    }
}
