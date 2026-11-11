package java.lang;
public final class System {
    private System() {}
    public static final java.io.PrintStream out=new java.io.PrintStream(false);
    public static final java.io.PrintStream err=new java.io.PrintStream(true);
    public static void arraycopy(Object src,int srcPos,Object dst,int dstPos,int length) { jbv.runtime.Support.arraycopy(src,srcPos,dst,dstPos,length); }
    public static int identityHashCode(Object o) { return jbv.runtime.Support.identityHash(o); }
    public static long currentTimeMillis() { return jbv.runtime.Support.clock(false); }
    public static long nanoTime() { return jbv.runtime.Support.clock(true); }
    public static void gc() { jbv.runtime.Support.collect(); }
    public static String lineSeparator() { return "\r\n"; }
}
