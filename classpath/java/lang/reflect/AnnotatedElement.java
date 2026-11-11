package java.lang.reflect;
import java.lang.annotation.*;
import java.util.ArrayList;
public interface AnnotatedElement {
 Annotation[] getDeclaredAnnotations();
 default Annotation[] getAnnotations(){
  Annotation[] own=getDeclaredAnnotations();if(!(this instanceof Class<?>))return own;
  Class<?> parent=((Class<?>)this).getSuperclass();if(parent==null)return own;
  ArrayList<Annotation> all=new ArrayList<>();for(Annotation a:own)all.add(a);
  for(Annotation a:parent.getAnnotations()){boolean present=false;for(Annotation b:own)if(b.annotationType()==a.annotationType())present=true;
   if(!present&&a.annotationType().getDeclaredAnnotation(Inherited.class)!=null)all.add(a);}
  return all.toArray(new Annotation[all.size()]);
 }
 default <T extends Annotation> T getAnnotation(Class<T> type){if(type==null)throw new NullPointerException();for(Annotation a:getAnnotations())if(a.annotationType()==type)return type.cast(a);return null;}
 default <T extends Annotation> T getDeclaredAnnotation(Class<T> type){if(type==null)throw new NullPointerException();for(Annotation a:getDeclaredAnnotations())if(a.annotationType()==type)return type.cast(a);return null;}
 default boolean isAnnotationPresent(Class<? extends Annotation> type){return getAnnotation(type)!=null;}
 @SuppressWarnings("unchecked") default <T extends Annotation> T[] getDeclaredAnnotationsByType(Class<T> type){
  if(type==null)throw new NullPointerException();Repeatable repeated=type.getDeclaredAnnotation(Repeatable.class);ArrayList<T> found=new ArrayList<>();
  for(Annotation a:getDeclaredAnnotations()){
   if(a.annotationType()==type)found.add(type.cast(a));
   else if(repeated!=null&&a.annotationType()==repeated.value())try{Method m=a.annotationType().getDeclaredMethod("value");m.setAccessible(true);for(T t:(T[])m.invoke(a))found.add(t);}catch(ReflectiveOperationException e){throw new IllegalStateException(e);}
  }
  return found.toArray((T[])Array.newInstance(type,found.size()));
 }
 default <T extends Annotation> T[] getAnnotationsByType(Class<T> type){T[] own=getDeclaredAnnotationsByType(type);if(own.length==0&&this instanceof Class<?> && type.getDeclaredAnnotation(Inherited.class)!=null){Class<?> parent=((Class<?>)this).getSuperclass();if(parent!=null)return parent.getAnnotationsByType(type);}return own;}
}
