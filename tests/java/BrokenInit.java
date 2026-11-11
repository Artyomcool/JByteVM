public class BrokenInit {
    static int value = divide(0);
    static int divide(int divisor) { return 1 / divisor; }
    public static int get() { return value; }
}
