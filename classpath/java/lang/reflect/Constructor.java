package java.lang.reflect;
import jbv.runtime.Reflection;
public final class Constructor<T> extends Executable {
 Constructor() {}
 public String getName(){return getDeclaringClass().getName();}
 @SuppressWarnings("unchecked") public TypeVariable<Constructor<T>>[] getTypeParameters(){return (TypeVariable<Constructor<T>>[])jbv.runtime.Generics.member(this,4);}
 @SuppressWarnings("unchecked") public T newInstance(Object... args)throws InstantiationException,IllegalAccessException,InvocationTargetException{return (T)Reflection.invoke(this,null,args);}
 public boolean equals(Object other){return other instanceof Constructor&&same((Constructor<?>)other);}
 public int hashCode(){return getName().hashCode();}
 public String toString(){return description(getName());}
}
