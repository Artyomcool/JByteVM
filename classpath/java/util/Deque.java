package java.util;
/** Defaults reduce every implementation to addFirst/addLast, pollFirst/pollLast, peekFirst/peekLast and the two iterators. */
public interface Deque<E> extends Queue<E>,SequencedCollection<E> {
    void addFirst(E e); void addLast(E e); E pollFirst(); E pollLast(); E peekFirst(); E peekLast(); Iterator<E> descendingIterator();
    default boolean offerFirst(E e) {addFirst(e);return true;}
    default boolean offerLast(E e) {addLast(e);return true;}
    default E getFirst() {if(isEmpty())throw new NoSuchElementException();return peekFirst();}
    default E getLast() {if(isEmpty())throw new NoSuchElementException();return peekLast();}
    default E removeFirst() {if(isEmpty())throw new NoSuchElementException();return pollFirst();}
    default E removeLast() {if(isEmpty())throw new NoSuchElementException();return pollLast();}
    default boolean removeFirstOccurrence(Object o) {return remove(o);}
    default boolean removeLastOccurrence(Object o) {Iterator<E> it=descendingIterator();while(it.hasNext())if(Objects.equals(o,it.next())){it.remove();return true;}return false;}
    default boolean offer(E e) {return offerLast(e);}
    default E remove() {return removeFirst();}
    default E poll() {return pollFirst();}
    default E element() {return getFirst();}
    default E peek() {return peekFirst();}
    default void push(E e) {addFirst(e);}
    default E pop() {return removeFirst();}
    default Deque<E> reversed() {return new ArrayDeque.Reversed<E>(this);}
}
