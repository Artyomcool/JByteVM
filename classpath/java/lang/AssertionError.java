package java.lang;
public class AssertionError extends Error {
    public AssertionError(){super();}
    public AssertionError(Object detail){super(String.valueOf(detail));if(detail instanceof Throwable)initCause((Throwable)detail);}
    public AssertionError(boolean detail){this((Object)String.valueOf(detail));}
    public AssertionError(char detail){this((Object)String.valueOf(detail));}
    public AssertionError(int detail){this((Object)String.valueOf(detail));}
    public AssertionError(long detail){this((Object)String.valueOf(detail));}
    public AssertionError(float detail){this((Object)String.valueOf(detail));}
    public AssertionError(double detail){this((Object)String.valueOf(detail));}
    public AssertionError(String message,Throwable cause){super(message,cause);}
}
