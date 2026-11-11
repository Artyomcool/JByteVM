package java.lang.reflect;
import jbv.runtime.Reflection;
public final class Method extends Executable {
 Method() {}
 public Object getDefaultValue(){return Reflection.info(this,4); }
 public String getName(){return name();}
 public Class<?> getReturnType(){return type();}
 public boolean isBridge(){return (getModifiers()&0x40)!=0;}
 public boolean isDefault(){return getDeclaringClass().isInterface()&&(getModifiers()&(Modifier.ABSTRACT|Modifier.STATIC|Modifier.PRIVATE))==0;}
 public Object invoke(Object receiver,Object... args) throws IllegalAccessException,InvocationTargetException {try{return Reflection.invoke(this,receiver,args);}catch(InstantiationException impossible){throw new AssertionError(impossible);}}
 public boolean equals(Object other){return other instanceof Method&&same((Method)other);}
 public int hashCode(){return getDeclaringClass().getName().hashCode()^getName().hashCode();}
 public String toString(){return description(Field.typeName(getReturnType())+" "+getDeclaringClass().getName()+"."+getName());}
}
