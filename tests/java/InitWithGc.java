public class InitWithGc {
    static { Objects.collectNative(); }
    public static int read(Objects.Node node) { return node.value; }
}
