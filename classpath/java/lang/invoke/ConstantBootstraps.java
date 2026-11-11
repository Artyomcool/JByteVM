package java.lang.invoke;
import java.util.Objects;
public final class ConstantBootstraps {
    private ConstantBootstraps() {}
    public static Object nullConstant(MethodHandles.Lookup lookup,String name,Class<?> type){Objects.requireNonNull(lookup);Objects.requireNonNull(name);if(type.isPrimitive())throw new IllegalArgumentException();return null;}
    public static Class<?> primitiveClass(MethodHandles.Lookup lookup,String name,Class<?> type){Objects.requireNonNull(lookup);if(type!=Class.class||name.length()!=1)throw new IllegalArgumentException();return jbv.runtime.Support.primitive(name.charAt(0));}
    public static Object getStaticFinal(MethodHandles.Lookup lookup,String name,Class<?> type,Class<?> declaring){return jbv.runtime.Support.staticFinal(lookup.lookupClass(),declaring,name,type);}
    public static Object getStaticFinal(MethodHandles.Lookup lookup,String name,Class<?> type){return getStaticFinal(lookup,name,type,type.isPrimitive()?jbv.runtime.Support.wrapperClass(type):type);}
    public static Object invoke(MethodHandles.Lookup lookup,String name,Class<?> type,MethodHandle target,Object... args)throws Throwable{Objects.requireNonNull(lookup);Objects.requireNonNull(name);Objects.requireNonNull(type);return target.invokeWithArguments(args);}
    public static Object explicitCast(MethodHandles.Lookup lookup,String name,Class<?> type,Object value){Objects.requireNonNull(lookup);Objects.requireNonNull(name);return jbv.runtime.Support.explicitCast(type,value);}
    public static <E extends Enum<E>> E enumConstant(MethodHandles.Lookup lookup,String name,Class<E> type){Objects.requireNonNull(lookup);return Enum.valueOf(type,name);}
}
