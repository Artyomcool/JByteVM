package java.util.stream;
import java.util.*;
import java.util.function.*;
public interface Collector<T,A,R> {
    Supplier<A> supplier(); BiConsumer<A,T> accumulator(); BinaryOperator<A> combiner(); Function<A,R> finisher(); Set<Characteristics> characteristics();
    @SuppressWarnings("unchecked") static <T,R> Collector<T,R,R> of(Supplier<R> s,BiConsumer<R,T> acc,BinaryOperator<R> combiner,Characteristics... ch){
        return new jbv.runtime.Collect(s,acc,combiner,null,ch,true);}
    @SuppressWarnings("unchecked") static <T,A,R> Collector<T,A,R> of(Supplier<A> s,BiConsumer<A,T> acc,BinaryOperator<A> combiner,Function<A,R> finisher,Characteristics... ch){
        return new jbv.runtime.Collect(s,acc,combiner,finisher,ch,false);}
    enum Characteristics {CONCURRENT,UNORDERED,IDENTITY_FINISH}
}
