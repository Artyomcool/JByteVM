import java.lang.invoke.*;
public class CondyValues {
    static int calls,failures;
    public static final int FIELD=Integer.parseInt("72");
    public enum Choice {A,B,C}
    public static int integer(MethodHandles.Lookup lookup,String name,Class<?> type,int a,int b){if(lookup.lookupClass()!=Condy.class||type!=int.class)throw new AssertionError();calls++;System.gc();return a+b;}
    public static long wide(MethodHandles.Lookup lookup,String name,Class<?> type,long value){calls++;return value+1;}
    public static Object text(MethodHandles.Lookup lookup,String name,Class<?> type,Object... args){calls++;System.gc();return new StringBuilder(name).append(':').append(args.length).append(':').append(args[0]).append(':').append(args[1]).toString();}
    public static Object failure(MethodHandles.Lookup lookup,String name,Class<?> type){failures++;throw new IllegalStateException("bootstrap");}
    public static Object badType(MethodHandles.Lookup lookup,String name,Class<?> type){return "wrong";}
    public static Object recurse(MethodHandles.Lookup lookup,String name,Class<?> type){return Condy.recurse();}
    public static Object handle(MethodHandles.Lookup lookup,String name,Class<?> type,MethodHandle handle,MethodType mt)throws Throwable{if(!mt.equals(handle.type()))throw new AssertionError();return (int)handle.invokeExact(7);}
    public static int target(int x){return x*3;}
    public static int constants(int unused){
        int a=Condy.integer();if(a!=42||Condy.integer()!=42)throw new AssertionError();
        if(Condy.wide()!=0x123456789abcdef1L)throw new AssertionError();
        String s=Condy.text();System.gc();if(s!=Condy.text()||!s.equals("text:2:17:hello"))throw new AssertionError();
        if(Condy.nil()!=null||Condy.primitive()!=int.class||Condy.fixed()!=72||Condy.nested()!=43||Condy.handle()!=21||Condy.choice()!=Choice.B)throw new AssertionError();
        return calls;
    }
    public static int errors(int unused){
        int n=0;for(int i=0;i<2;i++)try{Condy.failure();}catch(BootstrapMethodError e){if(e.getCause() instanceof IllegalStateException)n++;}
        try{Condy.badType();}catch(BootstrapMethodError e){n+=4;}
        try{Condy.recurse();}catch(StackOverflowError e){n+=8;}
        return n+failures*100;
    }
    public static int handles(int unused)throws Throwable{
        MethodHandles.Lookup lookup=MethodHandles.lookup();
        MethodHandle h=lookup.findStatic(CondyValues.class,"target",MethodType.methodType(int.class,int.class));
        int n=(int)h.invokeExact(9);n+=(int)h.invoke((byte)2);n+=(Integer)h.invokeWithArguments(4);
        try{long bad=(long)h.invokeExact(7);throw new AssertionError(bad);}catch(WrongMethodTypeException e){n++;}
        MethodHandle ctor=lookup.findConstructor(Box.class,MethodType.methodType(void.class,int.class));
        Box b=(Box)ctor.invokeExact(11);
        MethodHandle getter=lookup.findGetter(Box.class,"value",int.class),setter=lookup.findSetter(Box.class,"value",int.class);
        n+=(int)getter.invokeExact(b);setter.invokeExact(b,17);n+=(int)getter.invokeExact(b);
        MethodHandle virtual=lookup.findVirtual(Box.class,"plus",MethodType.methodType(int.class,int.class));
        n+=(int)virtual.invokeExact(b,3);
        MethodHandle varargs=lookup.findStatic(CondyValues.class,"sum",MethodType.methodType(int.class,int[].class));
        n+=(Integer)varargs.invokeWithArguments(1,2,3,4);
        n+=(int)varargs.invokeExact(new int[]{5,6});
        n+=lookup.findStaticGetter(CondyValues.class,"FIELD",int.class).invokeWithArguments().hashCode();
        return n;
    }
    public static int sum(int... values){int n=0;for(int v:values)n+=v;return n;}
    public static class Box {public int value;public Box(int n){value=n;}public int plus(int n){return value+n;}}
}
