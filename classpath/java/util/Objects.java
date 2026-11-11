package java.util;
import java.util.function.Supplier;
public final class Objects {
    private Objects() {}
    public static boolean equals(Object a,Object b) {return a==b||(a!=null&&a.equals(b));}
    public static int hashCode(Object a) {return a==null?0:a.hashCode();}
    public static int hash(Object... values) {if(values==null)return 0;int h=1;for(Object x:values)h=31*h+hashCode(x);return h;}
    public static String toString(Object x) {return String.valueOf(x);}
    public static String toString(Object x,String fallback) {return x==null?fallback:x.toString();}
    public static <T> T requireNonNull(T x) {if(x==null)throw new NullPointerException();return x;}
    public static <T> T requireNonNull(T x,String message) {if(x==null)throw new NullPointerException(message);return x;}
    public static <T> T requireNonNull(T x,Supplier<String> message) {if(x==null)throw new NullPointerException(message==null?null:message.get());return x;}
    public static <T> T requireNonNullElse(T x,T fallback) {return x==null?requireNonNull(fallback):x;}
    public static <T> T requireNonNullElseGet(T x,Supplier<? extends T> fallback) {return x==null?requireNonNull(requireNonNull(fallback).get()):x;}
    public static boolean isNull(Object x) {return x==null;}
    public static boolean nonNull(Object x) {return x!=null;}
    public static int checkIndex(int index,int length) {if(index<0||index>=length)throw new IndexOutOfBoundsException();return index;}
    public static int checkFromToIndex(int from,int to,int length) {if(from<0||to<from||to>length)throw new IndexOutOfBoundsException();return from;}
    public static int checkFromIndexSize(int from,int size,int length) {if(from<0||size<0||from>length||size>length-from)throw new IndexOutOfBoundsException();return from;}
    public static <T> int compare(T a,T b,Comparator<? super T> c) {return a==b?0:c.compare(a,b);}
}
