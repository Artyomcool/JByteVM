package java.lang.reflect;
public class InvocationTargetException extends ReflectiveOperationException {
 protected InvocationTargetException(){super(null,null);}
 public InvocationTargetException(Throwable target){super(null,target);}
 public InvocationTargetException(Throwable target,String message){super(message,target);}
 public Throwable getTargetException(){return getCause();}
}
