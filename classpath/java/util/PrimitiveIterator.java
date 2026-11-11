package java.util;
import java.util.function.*;
public interface PrimitiveIterator<T,C> extends Iterator<T> {
    void forEachRemaining(C action);
    interface OfInt extends PrimitiveIterator<Integer,IntConsumer> {
        int nextInt(); default Integer next(){return nextInt();}
        default void forEachRemaining(IntConsumer a){Objects.requireNonNull(a);while(hasNext())a.accept(nextInt());}
    }
    interface OfLong extends PrimitiveIterator<Long,LongConsumer> {
        long nextLong(); default Long next(){return nextLong();}
        default void forEachRemaining(LongConsumer a){Objects.requireNonNull(a);while(hasNext())a.accept(nextLong());}
    }
    interface OfDouble extends PrimitiveIterator<Double,DoubleConsumer> {
        double nextDouble(); default Double next(){return nextDouble();}
        default void forEachRemaining(DoubleConsumer a){Objects.requireNonNull(a);while(hasNext())a.accept(nextDouble());}
    }
}
