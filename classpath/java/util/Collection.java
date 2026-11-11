package java.util;
import java.util.function.*;
public interface Collection<E> extends Iterable<E> {
    int size(); boolean isEmpty(); boolean contains(Object x); Iterator<E> iterator();
    Object[] toArray(); <T> T[] toArray(T[] target);
    boolean add(E x); boolean remove(Object x); boolean containsAll(Collection<?> other);
    boolean addAll(Collection<? extends E> other); boolean removeAll(Collection<?> other); boolean retainAll(Collection<?> other); void clear();
    default java.util.stream.Stream<E> stream() {return jbv.runtime.Pipe.of(this);}
    default java.util.stream.Stream<E> parallelStream() {return stream();}
    default <T> T[] toArray(IntFunction<T[]> factory) {return toArray(factory.apply(0));}
    default boolean removeIf(Predicate<? super E> test) {Objects.requireNonNull(test);boolean changed=false;Iterator<E> it=iterator();while(it.hasNext())if(test.test(it.next())){it.remove();changed=true;}return changed;}
}
