package java.util.stream;
import java.util.*;
import java.util.function.*;
import jbv.runtime.Collect;
@SuppressWarnings({"unchecked","rawtypes"})
public final class Collectors {
    private Collectors(){}
    private static Collector c(int kind,int code,Object a,Object b,Object c,Object d){return new Collect(kind,code,a,b,c,d);}
    private static Collector n(Object x){return c(Collect.COLL,0,Objects.requireNonNull(x),null,null,null);}
    public static <T,C extends Collection<T>> Collector<T,?,C> toCollection(Supplier<C> s){return n(s);}
    public static <T> Collector<T,?,List<T>> toList(){return c(Collect.LIST,0,null,null,null,null);}
    public static <T> Collector<T,?,List<T>> toUnmodifiableList(){return c(Collect.ULIST,0,null,null,null,null);}
    public static <T> Collector<T,?,Set<T>> toSet(){return c(Collect.SET,0,null,null,null,null);}
    public static <T> Collector<T,?,Set<T>> toUnmodifiableSet(){return c(Collect.USET,0,null,null,null,null);}
    public static Collector<CharSequence,?,String> joining(){return joining("","","");}
    public static Collector<CharSequence,?,String> joining(CharSequence delimiter){return joining(delimiter,"","");}
    public static Collector<CharSequence,?,String> joining(CharSequence delimiter,CharSequence prefix,CharSequence suffix){
        return c(Collect.JOIN,0,delimiter.toString(),prefix.toString(),suffix.toString(),null);}
    public static <T,U,A,R> Collector<T,?,R> mapping(Function<? super T,? extends U> f,Collector<? super U,A,R> ds){return c(Collect.MAPPING,0,Objects.requireNonNull(f),Objects.requireNonNull(ds),null,null);}
    public static <T,U,A,R> Collector<T,?,R> flatMapping(Function<? super T,? extends Stream<? extends U>> f,Collector<? super U,A,R> ds){return c(Collect.FLATMAPPING,0,Objects.requireNonNull(f),Objects.requireNonNull(ds),null,null);}
    public static <T,A,R> Collector<T,?,R> filtering(Predicate<? super T> p,Collector<? super T,A,R> ds){return c(Collect.FILTERING,0,Objects.requireNonNull(p),Objects.requireNonNull(ds),null,null);}
    public static <T,A,R,RR> Collector<T,A,RR> collectingAndThen(Collector<T,A,R> ds,Function<R,RR> f){return c(Collect.THEN,0,Objects.requireNonNull(ds),Objects.requireNonNull(f),null,null);}
    public static <T> Collector<T,?,Long> counting(){return c(Collect.COUNT,0,null,null,null,null);}
    public static <T> Collector<T,?,Optional<T>> minBy(Comparator<? super T> cmp){return c(Collect.BEST,0,Objects.requireNonNull(cmp),null,null,null);}
    public static <T> Collector<T,?,Optional<T>> maxBy(Comparator<? super T> cmp){return c(Collect.BEST,1,Objects.requireNonNull(cmp),null,null,null);}
    private static Collector s(int code,Object f){return c(Collect.STATS,code,Objects.requireNonNull(f),null,null,null);}
    public static <T> Collector<T,?,Integer> summingInt(ToIntFunction<? super T> f){return s(0,f);}
    public static <T> Collector<T,?,Long> summingLong(ToLongFunction<? super T> f){return s(3,f);}
    public static <T> Collector<T,?,Double> summingDouble(ToDoubleFunction<? super T> f){return s(6,f);}
    public static <T> Collector<T,?,Double> averagingInt(ToIntFunction<? super T> f){return s(1,f);}
    public static <T> Collector<T,?,Double> averagingLong(ToLongFunction<? super T> f){return s(4,f);}
    public static <T> Collector<T,?,Double> averagingDouble(ToDoubleFunction<? super T> f){return s(7,f);}
    public static <T> Collector<T,?,IntSummaryStatistics> summarizingInt(ToIntFunction<? super T> f){return s(2,f);}
    public static <T> Collector<T,?,LongSummaryStatistics> summarizingLong(ToLongFunction<? super T> f){return s(5,f);}
    public static <T> Collector<T,?,DoubleSummaryStatistics> summarizingDouble(ToDoubleFunction<? super T> f){return s(8,f);}
    public static <T> Collector<T,?,T> reducing(T identity,BinaryOperator<T> op){return c(Collect.REDUCE,1,identity,null,Objects.requireNonNull(op),null);}
    public static <T> Collector<T,?,Optional<T>> reducing(BinaryOperator<T> op){return c(Collect.REDUCE,0,null,null,Objects.requireNonNull(op),null);}
    public static <T,U> Collector<T,?,U> reducing(U identity,Function<? super T,? extends U> f,BinaryOperator<U> op){return c(Collect.REDUCE,1,identity,Objects.requireNonNull(f),Objects.requireNonNull(op),null);}
    public static <T,K> Collector<T,?,Map<K,List<T>>> groupingBy(Function<? super T,? extends K> f){return groupingBy(f,toList());}
    public static <T,K,A,D> Collector<T,?,Map<K,D>> groupingBy(Function<? super T,? extends K> f,Collector<? super T,A,D> ds){
        return c(Collect.GROUP,0,Objects.requireNonNull(f),null,Objects.requireNonNull(ds),null);}
    public static <T,K,D,A,M extends Map<K,D>> Collector<T,?,M> groupingBy(Function<? super T,? extends K> f,Supplier<M> factory,Collector<? super T,A,D> ds){
        return c(Collect.GROUP,0,Objects.requireNonNull(f),Objects.requireNonNull(factory),Objects.requireNonNull(ds),null);}
    public static <T> Collector<T,?,Map<Boolean,List<T>>> partitioningBy(Predicate<? super T> p){return partitioningBy(p,toList());}
    public static <T,D,A> Collector<T,?,Map<Boolean,D>> partitioningBy(Predicate<? super T> p,Collector<? super T,A,D> ds){
        return c(Collect.PARTITION,0,Objects.requireNonNull(p),null,Objects.requireNonNull(ds),null);}
    private static Collector m(int code,Object k,Object v,Object merge,Object factory){return c(Collect.TOMAP,code,Objects.requireNonNull(k),Objects.requireNonNull(v),merge,factory);}
    public static <T,K,U> Collector<T,?,Map<K,U>> toMap(Function<? super T,? extends K> k,Function<? super T,? extends U> v){return m(0,k,v,null,null);}
    public static <T,K,U> Collector<T,?,Map<K,U>> toMap(Function<? super T,? extends K> k,Function<? super T,? extends U> v,BinaryOperator<U> merge){return m(0,k,v,Objects.requireNonNull(merge),null);}
    public static <T,K,U,M extends Map<K,U>> Collector<T,?,M> toMap(Function<? super T,? extends K> k,Function<? super T,? extends U> v,BinaryOperator<U> merge,Supplier<M> factory){
        return m(0,k,v,Objects.requireNonNull(merge),Objects.requireNonNull(factory));}
    public static <T,K,U> Collector<T,?,Map<K,U>> toUnmodifiableMap(Function<? super T,? extends K> k,Function<? super T,? extends U> v){return m(1,k,v,null,null);}
    public static <T,K,U> Collector<T,?,Map<K,U>> toUnmodifiableMap(Function<? super T,? extends K> k,Function<? super T,? extends U> v,BinaryOperator<U> merge){return m(1,k,v,Objects.requireNonNull(merge),null);}
    public static <T,R1,R2,R> Collector<T,?,R> teeing(Collector<? super T,?,R1> a,Collector<? super T,?,R2> b,BiFunction<? super R1,? super R2,R> merger){
        return c(Collect.TEE,0,Objects.requireNonNull(a),Objects.requireNonNull(b),Objects.requireNonNull(merger),null);}
}
