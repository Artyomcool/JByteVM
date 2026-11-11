package jbvhost;

/** File access provided by examples/run_host.c (jbytevm-run) to Java tools. */
public final class Host {
    private Host() {}
    public static native byte[] read(String path);
    public static native void write(String path, byte[] data);
    /** Plain file names (no directories) in a directory. */
    public static native String[] list(String dir);
}
