package java.lang.reflect;
import jbv.runtime.Reflection;
public class AccessibleObject implements AnnotatedElement {
 // Fixed VM layout; metadata is VM-owned and valid for its entire lifetime.
 long target; Class<?> owner; boolean override; int kind;
 public java.lang.annotation.Annotation[] getDeclaredAnnotations(){return (java.lang.annotation.Annotation[])Reflection.annotations(this,-1);}
 protected AccessibleObject() {}
 public void setAccessible(boolean flag){override=flag;}
 public static void setAccessible(AccessibleObject[] array,boolean flag){for(AccessibleObject a:array)if(a==null)throw new NullPointerException();for(AccessibleObject a:array)a.setAccessible(flag);}
 public final boolean trySetAccessible(){setAccessible(true);return true;}
 @Deprecated public boolean isAccessible(){return override;}
 public final boolean canAccess(Object receiver){return Reflection.access(this,receiver);}
 final boolean same(AccessibleObject other){return other!=null&&owner==other.owner&&target==other.target&&kind==other.kind;}
 final String name(){return (String)Reflection.info(this,0);}
 final Class<?> type(){return (Class<?>)Reflection.info(this,1);}
 final int flags(){return Reflection.flags(this);}
}
