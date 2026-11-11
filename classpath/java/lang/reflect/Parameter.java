package java.lang.reflect;
import java.lang.annotation.Annotation;
/** A parameter of a method or constructor; names come from MethodParameters (javac -parameters). */
public final class Parameter implements AnnotatedElement {
 private final Executable executable; private final int index; private final String name; private final int modifiers;
 Parameter(Executable executable,int index,String name,int modifiers){this.executable=executable;this.index=index;this.name=name;this.modifiers=modifiers;}
 public Executable getDeclaringExecutable(){return executable;}
 public boolean isNamePresent(){return name!=null;}
 public String getName(){return name!=null?name:"arg"+index;}
 public int getModifiers(){return modifiers;}
 public boolean isImplicit(){return (modifiers&0x8000)!=0;}
 public boolean isSynthetic(){return (modifiers&0x1000)!=0;}
 public boolean isVarArgs(){return executable.isVarArgs()&&index==executable.getParameterCount()-1;}
 public Class<?> getType(){return executable.getParameterTypes()[index];}
 public Type getParameterizedType(){Type[] generic=executable.getGenericParameterTypes();return generic.length==executable.getParameterCount()?generic[index]:getType();}
 public Annotation[] getDeclaredAnnotations(){return executable.getParameterAnnotations()[index];}
 public Annotation[] getAnnotations(){return getDeclaredAnnotations();}
 public boolean equals(Object other){return other instanceof Parameter p&&p.executable.equals(executable)&&p.index==index;}
 public int hashCode(){return executable.hashCode()^index;}
 public String toString(){
  StringBuilder s=new StringBuilder(Modifier.toString(modifiers));if(modifiers!=0)s.append(' ');
  String type=getParameterizedType().getTypeName();
  s.append(isVarArgs()&&type.endsWith("[]")?type.substring(0,type.length()-2)+"...":type);
  return s.append(' ').append(getName()).toString();
 }
}
