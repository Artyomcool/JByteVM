interface DefaultMethod { default int get() { return 1; } }
public class DefaultProbe implements DefaultMethod {
    public static int run() { return new DefaultProbe().get(); }
}
