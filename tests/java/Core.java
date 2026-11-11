public class Core {
    static int counter = 7;
    static native int bridge(int value);
    static native int leaf(int value);
    public static int entry(int value) { return 10 + bridge(value) + 1; }
    public static int callback(int value) { return leaf(value) + 3; }
    public static int recursive(int n) { return n == 0 ? 1 : n * recursive(n - 1); }
    public static int sum(int n) {
        int sum = 0;
        for (int i = 0; i < n; ++i) sum += i;
        return sum;
    }
    public static int arithmetic(int a, int b) { return (a + b) * (a - b) ^ (a & b) | (a >>> b); }
    public static int divide(int a, int b) { return a / b; }
    public static int remainder(int a, int b) { return a % b; }
    public static int shifts(int a, int b) { return (a << b) ^ (a >> b) ^ (a >>> b); }
    public static int negate(int a) { return -a; }
    public static int narrow(int a) { return (byte)a + (short)a + (char)a; }
    public static int dense(int n) {
        return switch (n) { case -1 -> 10; case 0 -> 20; case 1 -> 30; case 2 -> 40; default -> -1; };
    }
    public static int sparse(int n) {
        return switch (n) { case -1000 -> 3; case 50 -> 7; case 100000 -> 11; default -> -7; };
    }
    public static int tick() { return counter++; }
    public static int cross(int n) { return Helper.twice(n) + Helper.value; }
    public static int spin() { for (;;) {} }
    public static int recurseForever() { return recurseForever(); }
    public static long unsupportedLong() { return 42L; }
}
