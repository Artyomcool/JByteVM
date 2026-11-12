package jbv.runtime;

/** Private-to-this-runtime hooks; no DLL lookup, JIT, JNI or FFM. */
public final class Support {
    public static native Class<?> callerClass(int skip);
    public static native Class<?> methodTypeClass(String descriptor,int index);
    public static native java.lang.invoke.MethodHandle findHandle(Class<?> caller,Class<?> owner,String name,String descriptor,int kind);
    public static native Object invokeHandle(java.lang.invoke.MethodHandle handle,Object[] args)throws Throwable;
    public static native Object staticFinal(Class<?> caller,Class<?> owner,String name,Class<?> type);
    public static native Class<?> wrapperClass(Class<?> primitive);
    public static native Object explicitCast(Class<?> type,Object value);
    public static native Object enumValue(Class<?> type,String name);
    public static native StackTraceElement[] captureStackTrace(Throwable throwable);
    private Support() {}
    public static native Class<?> primitive(int descriptor);
    public static native void arraycopy(Object from,int fromAt,Object to,int toAt,int count);
    public static native Object[] newArrayLike(Object[] array,int length);
    public static native int identityHash(Object object);
    public static native long clock(boolean monotonic);
    public static native void write(String text,boolean error);
    public static native void collect();
    public static native int floatBits(float value);
    public static native float bitsFloat(int bits);
    public static native long doubleBits(double value);
    public static native double bitsDouble(long bits);
    public static native long parseFP(String value,boolean single);
    public static native double sqrt(double value);
    public static native double roundIntegral(double value,int mode);
    /** Copies the leading ASCII bytes of b[off, off+len) to out; returns their count. */
    public static native int ascii(byte[] b,int off,int len,char[] out);
    /** An entry of the application JAR (a resource), or null. */
    public static native byte[] resource(String name);
}
