package java.lang.reflect;
import jbv.runtime.Reflection;
public abstract class Executable extends AccessibleObject implements Member {
 Executable() {}
 public java.lang.annotation.Annotation[][] getParameterAnnotations(){return (java.lang.annotation.Annotation[][])Reflection.annotations(this,-2); }
 public Class<?> getDeclaringClass(){return owner;}
 public int getModifiers(){return flags();}
 public boolean isSynthetic(){return (getModifiers()&0x1000)!=0;}
 public boolean isVarArgs(){return (getModifiers()&0x80)!=0;}
 public Class<?>[] getParameterTypes(){return (Class<?>[])Reflection.info(this,2);}
 public int getParameterCount(){return getParameterTypes().length;}
 public Class<?>[] getExceptionTypes(){return (Class<?>[])Reflection.info(this,3);}
 final String description(String prefix){StringBuilder s=new StringBuilder();String mods=Modifier.toString(getModifiers()&0xd3f);if(!mods.isEmpty())s.append(mods).append(' ');s.append(prefix).append('(');Class<?>[] p=getParameterTypes();for(int i=0;i<p.length;i++){if(i!=0)s.append(',');s.append(Field.typeName(p[i]));}s.append(')');Class<?>[] e=getExceptionTypes();if(e.length!=0){s.append(" throws ");for(int i=0;i<e.length;i++){if(i!=0)s.append(',');s.append(e[i].getName());}}return s.toString();}
}
