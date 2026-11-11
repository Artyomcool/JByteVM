package java.util;
public interface ListIterator<E> extends Iterator<E> {
    boolean hasPrevious(); E previous(); int nextIndex(); int previousIndex();
    void set(E value); void add(E value);
}
