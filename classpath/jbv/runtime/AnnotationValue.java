package jbv.runtime;
import java.lang.annotation.Annotation;
import java.lang.reflect.*;
/** Superclass of small interpreter-only annotation implementations. */
public abstract class AnnotationValue implements Annotation {
 // Fixed VM layout; values are private copies and arrays are cloned on access.
 private Class<? extends Annotation> type; private Object[] values;
 public final Class<? extends Annotation> annotationType(){return type;}
 private static boolean equal(Object a,Object b){if(a==b)return true;if(a==null||b==null)return false;if(!a.getClass().isArray())return a.equals(b);if(a.getClass()!=b.getClass()||Array.getLength(a)!=Array.getLength(b))return false;for(int i=0;i<Array.getLength(a);i++)if(!equal(Array.get(a,i),Array.get(b,i)))return false;return true;}
 private static int hash(Object value){if(value==null)return 0;if(!value.getClass().isArray())return value.hashCode();int n=1;for(int i=0;i<Array.getLength(value);i++)n=31*n+hash(Array.get(value,i));return n;}
 private Method[] elements(){java.util.ArrayList<Method> result=new java.util.ArrayList<>();for(Method m:type.getDeclaredMethods())if(Modifier.isAbstract(m.getModifiers()))result.add(m);return result.toArray(new Method[result.size()]);}
 public final boolean equals(Object other){
  if(this==other)return true;if(!type.isInstance(other))return false;
  Method[] methods=elements();for(int i=0;i<methods.length;i++)try{methods[i].setAccessible(true);if(!equal(values[i],methods[i].invoke(other)))return false;}catch(ReflectiveOperationException e){return false;}return true;
 }
 public final int hashCode(){int hash=0;Method[] methods=elements();for(int i=0;i<methods.length;i++)hash+=(127*methods[i].getName().hashCode())^hash(values[i]);return hash;}
 private static void text(StringBuilder s,Object value){if(value!=null&&value.getClass().isArray()){s.append('{');for(int i=0;i<Array.getLength(value);i++){if(i!=0)s.append(", ");text(s,Array.get(value,i));}s.append('}');}else if(value instanceof String)s.append('"').append(value).append('"');else s.append(value);}
 public final String toString(){StringBuilder s=new StringBuilder("@").append(type.getName()).append('(');Method[] methods=elements();for(int i=0;i<methods.length;i++){if(i!=0)s.append(", ");s.append(methods[i].getName()).append('=');text(s,values[i]);}return s.append(')').toString();}
}
