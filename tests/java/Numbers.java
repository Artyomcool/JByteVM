public class Numbers {
    static final long LC = 0x123456789abcdef0L;
    static final double DC = -123.125;
    static long ls = LC;
    long l;
    double d;
    float f;
    Object ref;
    static native long bridge(long a, double b, Object c);
    public static long add(long a, long b) { return a + b; }
    public static long sub(long a, long b) { return a - b; }
    public static long mul(long a, long b) { return a * b; }
    public static long div(long a, long b) { return a / b; }
    public static long rem(long a, long b) { return a % b; }
    public static long neg(long a) { return -a; }
    public static long and(long a, long b) { return a & b; }
    public static long or(long a, long b) { return a | b; }
    public static long xor(long a, long b) { return a ^ b; }
    public static long shl(long a, int b) { return a << b; }
    public static long shr(long a, int b) { return a >> b; }
    public static long ushr(long a, int b) { return a >>> b; }
    public static int cmp(long a, long b) { return a < b ? -1 : a > b ? 1 : 0; }
    public static float add(float a, float b) { return a + b; }
    public static float sub(float a, float b) { return a - b; }
    public static float mul(float a, float b) { return a * b; }
    public static float div(float a, float b) { return a / b; }
    public static float rem(float a, float b) { return a % b; }
    public static float neg(float a) { return -a; }
    public static int cmp(float a, float b) { return a < b ? -1 : a > b ? 1 : a == b ? 0 : 2; }
    public static double add(double a, double b) { return a + b; }
    public static double sub(double a, double b) { return a - b; }
    public static double mul(double a, double b) { return a * b; }
    public static double div(double a, double b) { return a / b; }
    public static double rem(double a, double b) { return a % b; }
    public static double neg(double a) { return -a; }
    public static int cmp(double a, double b) { return a < b ? -1 : a > b ? 1 : a == b ? 0 : 2; }
    public static long i2l(int n) { return n; }
    public static float i2f(int n) { return n; }
    public static double i2d(int n) { return n; }
    public static int l2i(long n) { return (int)n; }
    public static float l2f(long n) { return n; }
    public static double l2d(long n) { return n; }
    public static int f2i(float n) { return (int)n; }
    public static long f2l(float n) { return (long)n; }
    public static double f2d(float n) { return n; }
    public static int d2i(double n) { return (int)n; }
    public static long d2l(double n) { return (long)n; }
    public static float d2f(double n) { return (float)n; }
    public static long shape(int n) {
        Numbers box = new Numbers();
        box.l = n + LC; box.d = DC + n; box.f = n + 1.25f;
        box.ref = new Object();
        long a = box.l++; double b = box.d++; float c = box.f++;
        long[] longs = new long[] { a, box.l, -1 };
        double[] doubles = new double[] { b, box.d, 1.0 };
        float[] floats = new float[] { c, box.f, 2.0f };
        longs[0] += longs[1]; doubles[0] += doubles[1]; floats[0] *= floats[1];
        long[][] matrix = new long[2][3]; matrix[1][2] = longs[0];
        ls = LC;
        return matrix[1][2] + (long)doubles[0] + (long)floats[0] + ls++;
    }
    public static int catchLong(int n) {
        try { return (int)(LC / n); }
        catch (ArithmeticException e) { return 71; }
    }
    public static long nativeChain(int n) { return bridge(LC + n, DC, new Object()); }
}
