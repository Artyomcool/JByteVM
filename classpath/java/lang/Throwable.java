package java.lang;
import java.io.PrintStream;
public class Throwable implements java.io.Serializable {
    // These first six fields are also initialized by VM-generated exceptions.
    private String detailMessage;
    private Throwable cause=this;
    private Throwable[] suppressed;
    private StackTraceElement[] stackTrace;
    private boolean enableSuppression=true,writableStackTrace=true;
    public Throwable(){fillInStackTrace();}
    public Throwable(String message){detailMessage=message;fillInStackTrace();}
    public Throwable(String message,Throwable cause){this.detailMessage=message;this.cause=cause;fillInStackTrace();}
    public Throwable(Throwable cause){this(cause==null?null:cause.toString(),cause);}
    protected Throwable(String message,Throwable cause,boolean enableSuppression,boolean writableStackTrace){detailMessage=message;this.cause=cause;this.enableSuppression=enableSuppression;this.writableStackTrace=writableStackTrace;if(writableStackTrace)fillInStackTrace();}
    public String getMessage(){return detailMessage;}
    public String getLocalizedMessage(){return getMessage();}
    public synchronized Throwable getCause(){return cause==this?null:cause;}
    public synchronized Throwable initCause(Throwable cause){if(this.cause!=this)throw new IllegalStateException();if(cause==this)throw new IllegalArgumentException();this.cause=cause;return this;}
    public String toString(){String name=getClass().getName(),message=getLocalizedMessage();return message==null?name:name+": "+message;}
    public synchronized Throwable fillInStackTrace(){if(writableStackTrace)stackTrace=jbv.runtime.Support.captureStackTrace(this);return this;}
    public StackTraceElement[] getStackTrace(){return stackTrace==null?new StackTraceElement[0]:stackTrace.clone();}
    public void setStackTrace(StackTraceElement[] trace){StackTraceElement[] copy=trace.clone();for(StackTraceElement e:copy)if(e==null)throw new NullPointerException();if(writableStackTrace)stackTrace=copy;}
    public final synchronized void addSuppressed(Throwable other){if(other==this)throw new IllegalArgumentException();if(other==null)throw new NullPointerException();if(!enableSuppression)return;int n=suppressed==null?0:suppressed.length;Throwable[] copy=new Throwable[n+1];if(n!=0)System.arraycopy(suppressed,0,copy,0,n);copy[n]=other;suppressed=copy;}
    public final synchronized Throwable[] getSuppressed(){return suppressed==null?new Throwable[0]:suppressed.clone();}
    public void printStackTrace(){printStackTrace(System.err);}
    public void printStackTrace(PrintStream out){java.util.Objects.requireNonNull(out);print(out,"","",null,new java.util.ArrayList<Throwable>());}
    private void print(PrintStream out,String indent,String caption,StackTraceElement[] enclosing,java.util.ArrayList<Throwable> visited){
        for(Throwable old:visited)if(old==this){out.println(indent+caption+"[CIRCULAR REFERENCE: "+this+"]");return;}
        visited.add(this);out.println(indent+caption+this);StackTraceElement[] trace=getStackTrace();int common=0;
        if(enclosing!=null)while(common<trace.length&&common<enclosing.length&&trace[trace.length-1-common].equals(enclosing[enclosing.length-1-common]))common++;
        for(int i=0;i<trace.length-common;i++)out.println(indent+"\tat "+trace[i]);
        if(common!=0)out.println(indent+"\t... "+common+" more");
        for(Throwable t:getSuppressed())t.print(out,indent+"\t","Suppressed: ",trace,visited);
        Throwable c=getCause();if(c!=null)c.print(out,indent,"Caused by: ",trace,visited);
    }
}
