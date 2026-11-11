package java.util.stream;
import java.util.*;
import java.util.function.*;
public interface Stream<T> extends BaseStream<T,Stream<T>> {
    Stream<T> filter(Predicate<? super T> p); <R> Stream<R> map(Function<? super T,? extends R> m);
    IntStream mapToInt(ToIntFunction<? super T> m); LongStream mapToLong(ToLongFunction<? super T> m); DoubleStream mapToDouble(ToDoubleFunction<? super T> m);
    <R> Stream<R> flatMap(Function<? super T,? extends Stream<? extends R>> m);
    IntStream flatMapToInt(Function<? super T,? extends IntStream> m); LongStream flatMapToLong(Function<? super T,? extends LongStream> m);
    DoubleStream flatMapToDouble(Function<? super T,? extends DoubleStream> m);
    <R> Stream<R> mapMulti(BiConsumer<? super T,? super Consumer<R>> m);
    Stream<T> distinct(); Stream<T> sorted(); Stream<T> sorted(Comparator<? super T> c); Stream<T> peek(Consumer<? super T> c);
    Stream<T> limit(long n); Stream<T> skip(long n); Stream<T> takeWhile(Predicate<? super T> p); Stream<T> dropWhile(Predicate<? super T> p);
    void forEach(Consumer<? super T> c); void forEachOrdered(Consumer<? super T> c);
    Object[] toArray(); <A> A[] toArray(IntFunction<A[]> generator);
    T reduce(T identity,BinaryOperator<T> op); Optional<T> reduce(BinaryOperator<T> op);
    <U> U reduce(U identity,BiFunction<U,? super T,U> acc,BinaryOperator<U> combiner);
    <R> R collect(Supplier<R> s,BiConsumer<R,? super T> acc,BiConsumer<R,R> combiner);
    <R,A> R collect(Collector<? super T,A,R> c); List<T> toList();
    Optional<T> min(Comparator<? super T> c); Optional<T> max(Comparator<? super T> c); long count();
    boolean anyMatch(Predicate<? super T> p); boolean allMatch(Predicate<? super T> p); boolean noneMatch(Predicate<? super T> p);
    Optional<T> findFirst(); Optional<T> findAny();
    @SuppressWarnings("unchecked") static <T> Builder<T> builder(){return (Builder<T>)jbv.runtime.Pipe.builder();}
    @SuppressWarnings("unchecked") static <T> Stream<T> empty(){return (Stream<T>)jbv.runtime.Pipe.empty(0);}
    static <T> Stream<T> of(T v){return of1(new Object[]{v});}
    static <T> Stream<T> ofNullable(T v){return v==null?Stream.<T>empty():of1(new Object[]{v});}
    @SafeVarargs static <T> Stream<T> of(T... v){return of1(v);}
    @SuppressWarnings("unchecked") private static <T> Stream<T> of1(Object[] v){return (Stream<T>)jbv.runtime.Pipe.array(0,v,0,v.length);}
    @SuppressWarnings("unchecked") static <T> Stream<T> iterate(T seed,UnaryOperator<T> f){return (Stream<T>)jbv.runtime.Pipe.iterate(0,seed,null,f);}
    @SuppressWarnings("unchecked") static <T> Stream<T> iterate(T seed,Predicate<? super T> hasNext,UnaryOperator<T> next){Objects.requireNonNull(hasNext);return (Stream<T>)jbv.runtime.Pipe.iterate(0,seed,hasNext,next);}
    @SuppressWarnings("unchecked") static <T> Stream<T> generate(Supplier<? extends T> s){return (Stream<T>)jbv.runtime.Pipe.generate(0,s);}
    @SuppressWarnings("unchecked") static <T> Stream<T> concat(Stream<? extends T> a,Stream<? extends T> b){return (Stream<T>)jbv.runtime.Pipe.concat(0,a,b);}
    interface Builder<T> extends Consumer<T> {void accept(T t); default Builder<T> add(T t){accept(t);return this;} Stream<T> build();}
}
