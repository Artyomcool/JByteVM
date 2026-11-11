import java.util.*;
import java.util.function.*;
public class LambdaValues {
    private final int offset;
    private LambdaValues(int offset){this.offset=offset;}
    private int instance(int n){return n+offset;}
    private static int twice(int n){return n*2;}
    interface Marker {}
    interface A {Object get();} interface B {String get();}
    interface Wide {double apply(int a,long b,float c);}
    interface Make {LambdaValues make(int n);}
    public static int basic(int seed){
        IntUnaryOperator simple=x->x+3,captured=x->x+seed,reference=LambdaValues::twice;
        LambdaValues object=new LambdaValues(seed);IntUnaryOperator bound=object::instance;
        BiFunction<LambdaValues,Integer,Integer> unbound=LambdaValues::instance;
        Make constructor=LambdaValues::new;LambdaValues made=constructor.make(seed+7);
        int n=simple.applyAsInt(4)+captured.applyAsInt(5)+reference.applyAsInt(6)+bound.applyAsInt(7)+unbound.apply(object,8)+made.offset;
        List<Integer> list=new ArrayList<>(List.of(1,2,3,4,5));list.removeIf(x->(x&1)==0);list.replaceAll(x->x+seed);list.sort(Integer::compare);
        final int[] sum={0};list.forEach(x->sum[0]+=x);return n+sum[0];
    }
    static class Parent {int value(){return 31;}}
    static class Child extends Parent {int value(){return 99;}IntSupplier parent(){return super::value;}}
    public static int advanced(int seed){
        Supplier<String> generic=()->"text";Function<String,Integer> length=String::length;
        Object intersection=(A&B&Marker)()->"bridge";
        IntUnaryOperator serial=(IntUnaryOperator&java.io.Serializable)(x->x+1);
        long captured=1234567890123L;double d=.25;
        Wide wide=(a,b,c)->a+b+c+captured+d;
        Consumer<StringBuilder> discard=StringBuilder::reverse;StringBuilder b=new StringBuilder("ab");discard.accept(b);
        int n=length.apply(generic.get())+((A)intersection).get().hashCode()+((B)intersection).get().length()+serial.applyAsInt(seed);
        n+=new Child().parent().getAsInt();n+=(int)wide.apply(seed,7L,.5f);n+=b.toString().hashCode();
        Function<Integer,Long> widening=Integer::longValue;ToLongFunction<Integer> primitive=Integer::intValue;
        n+=widening.apply(5)+primitive.applyAsLong(7);
        Supplier<int[]> array=()->new int[seed&15];n+=array.get().length;
        return n;
    }
    public static int errors(int seed){
        int n=0;String s=null;try{Supplier<Integer> f=s::length;f.get();}catch(NullPointerException e){n++;}
        Function<String,Integer> f=x->x.length();try{((Function)f).apply(Integer.valueOf(seed));}catch(ClassCastException e){n+=2;}
        return n;
    }
    public static void main(String[] args){for(int n:new int[]{0,1,-1,17,12345}){System.out.println(basic(n));System.out.println(advanced(n));System.out.println(errors(n));}}
}
