public class Diagnostics {
    static class Quiet extends RuntimeException {Quiet(){super("quiet",null,false,false);}}
    static Throwable leaf(){return new IllegalStateException("detail");}
    public static String trace(){Throwable t=leaf();StackTraceElement[] a=t.getStackTrace();return a[0].toString()+"|"+a[1].toString();}
    public static int semantics(int unused){
        int n=0;Throwable cause=new IllegalArgumentException("cause");Throwable t=new RuntimeException(cause);
        if(t.getMessage().equals(cause.toString())&&t.getCause()==cause)n++;
        Quiet q=new Quiet();q.addSuppressed(t);q.fillInStackTrace();q.setStackTrace(t.getStackTrace());if(q.getSuppressed().length==0&&q.getStackTrace().length==0)n+=2;
        StackTraceElement[] frame={new StackTraceElement("Example","method","Example.java",17)};t.setStackTrace(frame);frame[0]=null;
        StackTraceElement[] copy=t.getStackTrace();if(copy[0].getLineNumber()==17&&copy[0].toString().equals("Example.method(Example.java:17)"))n+=4;copy[0]=null;if(t.getStackTrace()[0]!=null)n+=8;
        try{t.initCause(null);}catch(IllegalStateException e){n+=16;}
        try{q.addSuppressed(null);}catch(NullPointerException e){n+=32;}
        try{t.setStackTrace(new StackTraceElement[]{null});}catch(NullPointerException e){n+=64;}
        try{Object o=null;o.hashCode();}catch(NullPointerException e){StackTraceElement f=e.getStackTrace()[0];if(f.getClassName().equals("Diagnostics")&&f.getMethodName().equals("semantics")&&f.getLineNumber()>0)n+=128;}
        ExceptionInInitializerError init=new ExceptionInInitializerError(cause);
        if(init.getMessage()==null&&init.getException()==cause&&init.getCause()==cause)n+=256;
        try{new ExceptionInInitializerError().initCause(cause);}catch(IllegalStateException e){n+=512;}
        return n;
    }
    public static int print(int unused){
        Throwable a=new RuntimeException("outer"),b=new IllegalArgumentException("inner");
        StackTraceElement frame=new StackTraceElement("Example","method","Example.java",17);
        a.setStackTrace(new StackTraceElement[]{frame});b.setStackTrace(new StackTraceElement[]{frame});a.initCause(b);a.addSuppressed(new Quiet());a.printStackTrace();return 1;
    }
    public static void main(String[] args){if(args.length==0)System.out.print(trace());else print(0);}
    public static int memory(int unused){try{int[] a=new int[1000000];return a.length;}catch(OutOfMemoryError e){return 42;}}
    public static Throwable[] memoryRepeated(){Throwable[] errors=new Throwable[64];for(int i=0;i<errors.length;i++)try{int[] a=new int[1000000];}catch(OutOfMemoryError e){errors[i]=e;}return errors;}
    static int recurse(int n){return recurse(n+1);}
    public static int stack(int unused){try{return recurse(0);}catch(StackOverflowError e){return 17;}}
}
