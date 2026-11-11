import java.io.Serializable;
import java.lang.reflect.*;
import java.util.*;
/** Generic reflection: compiled with -parameters; results hashed via toString/equals only
 * (Type hash codes depend on Class identity hashes, which differ between VMs). */
public class GenericValues {
    interface Shape<T extends Number & Comparable<T>> { T size(); }
    static class Base<K,V> { }
    static class Holder<E extends Comparable<? super E>> extends Base<String,List<E>> implements Shape<Integer>, Serializable {
        public List<? extends Number> numbers;
        public Map<String,List<int[]>> nested;
        public E[] items;
        public List<E>[] lists;
        public Map.Entry<E,? super Integer> entry;
        public int plain;
        public String[] names;
        public Holder(final List<E> source,int count) { }
        public Integer size() { return 0; }
        public <X extends Throwable,R> R apply(Map<? super X,R> table,X key,final int... rest) throws X,java.io.IOException { return null; }
        public static <T> T[] fill(T[] target,List<? extends T> from) { return target; }
        public void raw(List list,Object value) { }
        class Inner<Q> { public Inner<Q> self; public Holder<E>.Inner<String> other; }
    }

    static int h;
    static void mix(String s){h=h*31+s.hashCode();}
    static void mix(boolean b){h=h*31+(b?1:0);}
    static void types(Type[] types){mix(String.valueOf(types.length));for(Type t:types)describe(t);}
    static void describe(Type t){
        if(t==null){mix("null");return;}
        mix(t.getTypeName());mix(t.toString());
        if(t instanceof ParameterizedType p){mix("P");describe(p.getRawType());describe(p.getOwnerType());types(p.getActualTypeArguments());}
        else if(t instanceof WildcardType w){mix("W");types(w.getUpperBounds());types(w.getLowerBounds());}
        else if(t instanceof GenericArrayType g){mix("A");describe(g.getGenericComponentType());}
        else if(t instanceof TypeVariable<?> v){mix("V");mix(v.getName());GenericDeclaration d=v.getGenericDeclaration();mix(d instanceof Class<?> c?c.getName():String.valueOf(d));
            for(Type b:v.getBounds())mix(b.getTypeName());}
        else if(t instanceof Class<?> c){mix("C");mix(c.getName());}
    }
    static void parameters(Executable e){
        for(Parameter p:e.getParameters()){mix(p.getName());mix(p.toString());mix(String.valueOf(p.getModifiers()));mix(p.isNamePresent());mix(p.isVarArgs());
            mix(p.getType().getName());describe(p.getParameterizedType());mix(p.equals(e.getParameters()[0]));}
    }
    public static int generics(int seed) throws Exception {
        h=seed;
        Class<?> c=Holder.class;
        describe(c.getGenericSuperclass());types(c.getGenericInterfaces());types(c.getTypeParameters());
        types(Shape.class.getTypeParameters());describe(Shape.class.getGenericSuperclass());types(Shape.class.getGenericInterfaces());
        describe(Object.class.getGenericSuperclass());describe(int.class.getGenericSuperclass());types(String[].class.getGenericInterfaces());
        mix(int[][].class.getTypeName());mix(String[].class.getTypeName());mix(c.getTypeName());
        for(String name:new String[]{"numbers","nested","items","lists","entry","plain","names"}){Field f=c.getField(name);describe(f.getGenericType());mix(f.getGenericType().equals(c.getField(name).getGenericType()));}
        Method apply=null,fill=null,raw=null;
        for(Method m:c.getDeclaredMethods()){if(m.getName().equals("apply"))apply=m;if(m.getName().equals("fill"))fill=m;if(m.getName().equals("raw"))raw=m;}
        for(Method m:new Method[]{apply,fill,raw}){
            mix(m.getName());types(m.getTypeParameters());describe(m.getGenericReturnType());types(m.getGenericParameterTypes());types(m.getGenericExceptionTypes());parameters(m);
        }
        Constructor<?> k=c.getConstructor(List.class,int.class);types(k.getGenericParameterTypes());types(k.getTypeParameters());parameters(k);
        Class<?> inner=Holder.Inner.class;types(inner.getTypeParameters());describe(inner.getField("self").getGenericType());describe(inner.getField("other").getGenericType());
        TypeVariable<?> e=c.getTypeParameters()[0];mix(e.equals(c.getTypeParameters()[0]));mix(e.equals(Shape.class.getTypeParameters()[0]));
        Type a=c.getField("lists").getGenericType(),b=c.getField("lists").getGenericType();mix(a.equals(b));mix(a.equals(c.getField("items").getGenericType()));
        ParameterizedType nested=(ParameterizedType)c.getField("nested").getGenericType();mix(nested.getActualTypeArguments()[1].equals(c.getField("nested").getGenericType()));
        Type[] args=nested.getActualTypeArguments();args[0]=null;mix(nested.getActualTypeArguments()[0]!=null);
        return h;
    }
}
