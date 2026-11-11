package java.util;
import java.util.function.UnaryOperator;
public interface List<E> extends SequencedCollection<E> {
    E get(int index); E set(int index,E value); void add(int index,E value); E remove(int index);
    int indexOf(Object value); int lastIndexOf(Object value);
    boolean addAll(int index,Collection<? extends E> other);
    ListIterator<E> listIterator(); ListIterator<E> listIterator(int index); List<E> subList(int from,int to);
    default void replaceAll(UnaryOperator<E> operator) {Objects.requireNonNull(operator);ListIterator<E> it=listIterator();while(it.hasNext())it.set(operator.apply(it.next()));}
    @SuppressWarnings("unchecked") default void sort(Comparator<? super E> comparator) {
        Object[] a=toArray();jbv.runtime.Collections.sort(a,comparator);
        ListIterator<E> it=listIterator();for(Object x:a){it.next();it.set((E)x);}
    }
    default void addFirst(E value) {add(0,value);}
    default void addLast(E value) {add(value);}
    default E getFirst() {if(isEmpty())throw new NoSuchElementException();return get(0);}
    default E getLast() {if(isEmpty())throw new NoSuchElementException();return get(size()-1);}
    default E removeFirst() {if(isEmpty())throw new NoSuchElementException();return remove(0);}
    default E removeLast() {if(isEmpty())throw new NoSuchElementException();return remove(size()-1);}
    default List<E> reversed() {return new jbv.runtime.Collections.ReverseList<E>(this);}
    // Fixed-arity factories are emitted by generate_factories.py.
    static <E> List<E> of(E... values) {return jbv.runtime.Collections.immutableList(values);}
    static <E> List<E> copyOf(Collection<? extends E> source) {return jbv.runtime.Collections.immutableList(source.toArray());}
    // BEGIN GENERATED FACTORIES
    static <E> List<E> of(){return jbv.runtime.Collections.immutableList(new Object[]{});}
    static <E> List<E> of(E e0){return jbv.runtime.Collections.immutableList(new Object[]{e0});}
    static <E> List<E> of(E e0,E e1){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1});}
    static <E> List<E> of(E e0,E e1,E e2){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2});}
    static <E> List<E> of(E e0,E e1,E e2,E e3){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2,e3});}
    static <E> List<E> of(E e0,E e1,E e2,E e3,E e4){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2,e3,e4});}
    static <E> List<E> of(E e0,E e1,E e2,E e3,E e4,E e5){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2,e3,e4,e5});}
    static <E> List<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2,e3,e4,e5,e6});}
    static <E> List<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6,E e7){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2,e3,e4,e5,e6,e7});}
    static <E> List<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6,E e7,E e8){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2,e3,e4,e5,e6,e7,e8});}
    static <E> List<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6,E e7,E e8,E e9){return jbv.runtime.Collections.immutableList(new Object[]{e0,e1,e2,e3,e4,e5,e6,e7,e8,e9});}
    // END GENERATED FACTORIES
}
