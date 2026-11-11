package java.lang.invoke;
public final class MethodHandle {
    // Fixed private layout consumed by dynamic.c. Metadata lives as long as VM.
    private final long target=0, owner=0;
    private final int kind=0;
    private final MethodType type=null;
    private final Class<?> caller=null;
    private MethodHandle() {}
    public MethodType type(){return type;}
    public Object invokeWithArguments(Object... args)throws Throwable{return jbv.runtime.Support.invokeHandle(this,args);}
    public Object invokeWithArguments(java.util.List<?> args)throws Throwable{return invokeWithArguments(args.toArray());}
    public final native Object invokeExact(Object... args)throws Throwable;
    public final native Object invoke(Object... args)throws Throwable;
    public String toString(){return "MethodHandle"+type;}
}
