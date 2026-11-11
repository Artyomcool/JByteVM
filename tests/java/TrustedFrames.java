public class TrustedFrames {
    static native int checkpoint();
    static class Box {
        int value;
        Box(int n) { value = n; }
    }
    static int mixed(Box first, long wide, double real, Box last, int[] array) {
        int live = checkpoint();
        return first.value + (int)wide + (int)real + last.value + array[0] + live * 1000;
    }
    public static int roots(int n) {
        return mixed(new Box(n), 0x1234567800000005L, 7.25, new Box(n + 1), new int[] {9});
    }
    static int leaveReference(int n) {
        Box old = new Box(n);
        return old.value;
    }
    static int freshFrame() {
        int live = checkpoint();
        Box later = null;
        return live + (later == null ? 0 : later.value);
    }
    public static int reuse(int n) {
        leaveReference(n);
        return freshFrame();
    }
    public static Box make(int n) { return new Box(n); }
    public static int integerBits(int bits) { return checkpoint() + (bits & 0); }
}
