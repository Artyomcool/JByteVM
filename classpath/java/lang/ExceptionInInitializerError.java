package java.lang;
public class ExceptionInInitializerError extends LinkageError {
    public ExceptionInInitializerError(){super(null,null);}
    public ExceptionInInitializerError(String message){super(message,null);}
    public ExceptionInInitializerError(Throwable cause){super(null,cause);}
    public Throwable getException(){return getCause();}
}
