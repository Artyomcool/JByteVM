package java.util;
public interface SortedSet<E> extends Set<E>,SequencedSet<E> {
    Comparator<? super E> comparator(); E first(); E last();
    SortedSet<E> subSet(E from,E to); SortedSet<E> headSet(E to); SortedSet<E> tailSet(E from);
}
