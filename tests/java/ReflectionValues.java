import java.lang.reflect.*;
public class ReflectionValues {
    public interface Face { default int answer(){return 7;} static int stat(){return 1;} }
    public interface Ancestor { int K=31; int virtual(); }
    public static class Base implements Face,Ancestor {
        public int number=12;
        public long wide=15;
        public Object object;
        public final int fixed=8;
        private int hidden=19;
        public static int shared=5;
        public static final Integer constant=4;
        public Base() {}
        public Base(int n){number=n;}
        private Base(String text){number=text.length();}
        public int virtual(){return 11;}
        public Number result(){return 3;}
        public int add(int a,long b){return (int)(number+a+b);}
        public static double twice(double value){return 2*value;}
        public void boom()throws Exception{throw new Exception("target");}
        public void nothing() {}
        private int secret(){return hidden;}
        public void varargs(int... a){}
    }
    public static class Derived extends Base {
        public Derived(){super(21);}
        public int virtual(){return 23;}
        public Integer result(){return 6;}
    }
    public static abstract class Abstract { public Abstract(){} }
    public enum Choice {ONE}
    public static class Broken {static int n=fail();static int fail(){throw new IllegalStateException();}public static int read(){return n;}}
    public static class Throwing {public Throwing(){throw new IllegalStateException();}}
    public static class Lazy {static int n=initialized();public static int read(){return n;}}
    static int initializedCount;
    static int initialized(){return ++initializedCount;}
    public static int metadata(int ignored)throws Exception {
        int n=0;
        Method m=Base.class.getDeclaredMethod("add",int.class,long.class);
        if(m.getName().equals("add")&&m.getReturnType()==int.class&&m.getParameterCount()==2&&m.getDeclaringClass()==Base.class)n|=1;
        if(Base.class.getDeclaredConstructor(int.class).getName().equals(Base.class.getName()))n|=2;
        if(Base.class.getDeclaredMethod("boom").getExceptionTypes()[0]==Exception.class)n|=4;
        if(Base.class.getDeclaredMethod("varargs",int[].class).isVarArgs())n|=8;
        if(Base.class.getMethod("answer").isDefault())n|=16;
        if(Derived.class.getMethod("result").getReturnType()==Integer.class)n|=32;
        int bridges=0,returns=0;for(Method x:Derived.class.getDeclaredMethods()){if(x.isBridge())bridges++;if(x.getName().equals("result"))returns++;}
        if(bridges==1&&returns==2)n|=64;
        if(int.class.getDeclaredMethods().length==0&&String[].class.getDeclaredConstructors().length==0)n|=128;
        return n;
    }
    public static int enumeration(int ignored)throws Exception {
        int n=0;Method[] a=Base.class.getDeclaredMethods(),b=Base.class.getDeclaredMethods();if(a!=b&&a[0]!=b[0]&&a[0].equals(b[0]))n|=1;
        a[0].setAccessible(true);if(!b[0].isAccessible())n|=2;
        int virtual=0,result=0;for(Method m:Derived.class.getMethods()){if(m.getName().equals("virtual"))virtual++;if(m.getName().equals("result"))result++;}
        if(virtual==1&&result==2)n|=4;
        try{Derived.class.getMethod("stat");}catch(NoSuchMethodException e){n|=8;}
        if(Face.class.getMethods().length==2)n|=16;
        if(Base.class.getField("K").getDeclaringClass()==Ancestor.class)n|=32;
        if(Base.class.getDeclaredConstructors().length==3&&Base.class.getConstructors().length==2)n|=64;
        if(Base.class.getInterfaces().length==2&&int[].class.getInterfaces().length==2)n|=128;
        return n;
    }
    public static int calls(int ignored)throws Exception {
        Base b=new Derived();int n=0;
        if((Integer)Base.class.getMethod("virtual").invoke(b)==23)n|=1;
        if((Integer)Ancestor.class.getMethod("virtual").invoke(b)==23)n|=2;
        if((Integer)Base.class.getMethod("add",int.class,long.class).invoke(b,(byte)2,3)==26)n|=4;
        if((Double)Base.class.getMethod("twice",double.class).invoke(new Object(),2L)==4)n|=8;
        if(Base.class.getMethod("nothing").invoke(b,(Object[])null)==null)n|=16;
        if(Base.class.getConstructor(int.class).newInstance((short)32).number==32)n|=32;
        Constructor<Base> c=Base.class.getDeclaredConstructor(String.class);c.setAccessible(true);if(c.newInstance("hello").number==5)n|=64;
        if((Integer)Base.class.getMethod("answer").invoke(b)==7)n|=128;
        return n;
    }
    public static int errors(int ignored)throws Exception {
        Base b=new Base();int n=0;Method m=Base.class.getMethod("add",int.class,long.class);
        try{m.invoke(b,2L,3);}catch(IllegalArgumentException e){n|=1;}
        try{m.invoke(b,null,3);}catch(IllegalArgumentException e){n|=2;}
        try{m.invoke(new Object(),2,3);}catch(IllegalArgumentException e){n|=4;}
        try{m.invoke(null,2,3);}catch(NullPointerException e){n|=8;}
        try{Base.class.getMethod("boom").invoke(b);}catch(InvocationTargetException e){if(e.getTargetException()==e.getCause()&&e.getCause().getMessage().equals("target"))n|=16;}
        try{Throwing.class.getConstructor().newInstance();}catch(InvocationTargetException e){if(e.getCause() instanceof IllegalStateException)n|=32;}
        try{Abstract.class.getConstructor().newInstance();}catch(InstantiationException e){n|=64;}
        Constructor<?> c=Choice.class.getDeclaredConstructors()[0];c.setAccessible(true);try{c.newInstance("X",4);}catch(IllegalArgumentException e){n|=128;}
        return n;
    }
    public static int fields(int ignored)throws Exception {
        Base b=new Base();int n=0;Field f=Base.class.getField("number");
        f.set(b,(byte)23);if(f.getLong(b)==23&&((Integer)f.get(b))==23)n|=1;
        try{f.setLong(b,42);}catch(IllegalArgumentException e){n|=2;}
        try{f.getByte(b);}catch(IllegalArgumentException e){n|=4;}
        Field object=Base.class.getField("object");object.set(b,123);
        try{object.getInt(b);}catch(IllegalArgumentException e){n|=8;}
        try{object.setInt(b,11);}catch(IllegalArgumentException e){n|=16;}
        Field fixed=Base.class.getField("fixed");try{fixed.setInt(b,33);}catch(IllegalAccessException e){n|=32;}
        fixed.setAccessible(true);fixed.setInt(b,34);if(fixed.getInt(b)==34)n|=64;
        Field constant=Base.class.getField("constant");constant.setAccessible(true);try{constant.set(null,3);}catch(IllegalAccessException e){n|=128;}
        return n;
    }
    public static int arrays(int ignored)throws Exception {
        int n=0;Object a=Array.newInstance(long.class,3);Array.setByte(a,1,(byte)42);if(Array.getLong(a,1)==42&&Array.getLength(a)==3)n|=1;
        if(Array.newInstance(String.class,2,3).getClass()==String[][].class)n|=2;
        if(Array.newInstance(int[].class,2,3).getClass()==int[][][].class)n|=4;
        try{Array.getInt(a,1);}catch(IllegalArgumentException e){n|=8;}
        Object[] refs={4};try{Array.getInt(refs,0);}catch(IllegalArgumentException e){n|=16;}
        try{Array.setInt(refs,0,3);}catch(IllegalArgumentException e){n|=32;}
        char[] chars=(char[])Array.newInstance(char.class,2);Array.setChar(chars,1,'x');if(Array.getInt(chars,1)==120)n|=64;
        try{Array.newInstance(void.class,3);}catch(IllegalArgumentException e){n|=128;}
        return n;
    }
    public static int initialize(int ignored)throws Exception {
        initializedCount=0;int n=0;
        Class<?> c=Class.forName("ReflectionValues$Lazy",false,ReflectionValues.class.getClassLoader());Method m=c.getMethod("read");if(initializedCount==0)n|=1;
        if((Integer)m.invoke(null)==1&&initializedCount==1)n|=2;
        if(Class.forName("[[Ljava.lang.String;")==String[][].class)n|=4;
        try{Class.forName("missing.Type");}catch(ClassNotFoundException e){n|=8;}
        try{Class.forName("int");}catch(ClassNotFoundException e){n|=16;}
        Method read=Broken.class.getMethod("read");try{read.invoke(null);}catch(ExceptionInInitializerError e){n|=32;}
        try{read.invoke(null);}catch(NoClassDefFoundError e){n|=64;}
        if(Modifier.isAbstract(String[].class.getModifiers())&&Modifier.isPublic(int.class.getModifiers()))n|=128;
        return n;
    }
    public static int churn(int count)throws Exception {
        int sum=0;for(int i=0;i<count;i++){Method m=Base.class.getMethod("add",int.class,long.class);Base b=Base.class.getConstructor(int.class).newInstance(i);sum+=(Integer)m.invoke(b,2,3L);}
        return sum;
    }
    public static native int callback(int n);
    public static int reentry(int n)throws Exception{return (Integer)ReflectionValues.class.getMethod("callback",int.class).invoke(null,n);}
}
