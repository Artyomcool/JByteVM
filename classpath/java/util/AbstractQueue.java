package java.util;
public abstract class AbstractQueue<E> extends AbstractCollection<E> implements Queue<E> {
    protected AbstractQueue() {}
    public boolean add(E e) {if(offer(e))return true;throw new IllegalStateException("Queue full");}
    public E remove() {E x=poll();if(x==null)throw new NoSuchElementException();return x;}
    public E element() {E x=peek();if(x==null)throw new NoSuchElementException();return x;}
    public void clear() {while(poll()!=null);}
    public boolean addAll(Collection<? extends E> c) {if(Objects.requireNonNull(c)==this)throw new IllegalArgumentException();return super.addAll(c);}
}
