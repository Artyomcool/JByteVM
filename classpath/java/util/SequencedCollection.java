package java.util;
public interface SequencedCollection<E> extends Collection<E> {
    SequencedCollection<E> reversed();
    default void addFirst(E e) {throw new UnsupportedOperationException();}
    default void addLast(E e) {throw new UnsupportedOperationException();}
    default E getFirst() {return iterator().next();}
    default E getLast() {return reversed().iterator().next();}
    default E removeFirst() {Iterator<E> i=iterator();E e=i.next();i.remove();return e;}
    default E removeLast() {Iterator<E> i=reversed().iterator();E e=i.next();i.remove();return e;}
}
