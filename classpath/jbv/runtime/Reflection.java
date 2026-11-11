package jbv.runtime;
import java.lang.reflect.*;
/** VM-private metadata and interpreter operations, independent of MethodHandle. */
public final class Reflection {
 public static native Object annotations(Object element,int parameter);
 private Reflection() {}
 public static native Object info(AccessibleObject member,int what);
 public static native int flags(AccessibleObject member);
 public static native Object invoke(AccessibleObject member,Object receiver,Object[] args) throws IllegalAccessException,InvocationTargetException,InstantiationException;
 public static native Object field(AccessibleObject member,Object receiver,Object value,int operation) throws IllegalAccessException;
 public static native boolean access(AccessibleObject member,Object receiver);
 public static native Object array(Object array,int index,Object value,int op);
 public static native Object convert(Object value,int code);
}
