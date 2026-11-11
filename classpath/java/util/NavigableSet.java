package java.util;
public interface NavigableSet<E> extends SortedSet<E> {
    E lower(E e); E floor(E e); E ceiling(E e); E higher(E e); E pollFirst(); E pollLast();
    NavigableSet<E> descendingSet(); Iterator<E> descendingIterator();
    NavigableSet<E> subSet(E from,boolean fromInclusive,E to,boolean toInclusive);
    NavigableSet<E> headSet(E to,boolean inclusive); NavigableSet<E> tailSet(E from,boolean inclusive);
    default NavigableSet<E> reversed() {return descendingSet();}
}
