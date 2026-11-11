package java.util;
/** Circular power-of-two array; logical index i lives at a[(head+i)&mask]. */
public class ArrayDeque<E> extends AbstractCollection<E> implements Deque<E>,Cloneable,java.io.Serializable {
    private Object[] a;private int head,n,mods;
    public ArrayDeque(){a=new Object[16];}
    public ArrayDeque(int capacity){int c=1;while(c<capacity&&c<1<<30)c<<=1;a=new Object[c];}
    public ArrayDeque(Collection<? extends E> c){this(c.size());addAll(c);}
    public int size(){return n;}
    private int slot(int i){return (head+i)&(a.length-1);}
    @SuppressWarnings("unchecked") private E at(int i){return (E)a[slot(i)];}
    private void room(Object e){Objects.requireNonNull(e);mods++;if(n==a.length){Object[] b=new Object[n*2];for(int i=0;i<n;i++)b[i]=a[slot(i)];a=b;head=0;}n++;}
    public void addFirst(E e){room(e);head=slot(-1);a[head]=e;}
    public void addLast(E e){room(e);a[slot(n-1)]=e;}
    public boolean add(E e){addLast(e);return true;}
    public E peekFirst(){return at(0);}
    public E peekLast(){return at(n-1);}
    public E pollFirst(){return n==0?null:delete(0);}
    public E pollLast(){return n==0?null:delete(n-1);}
    /** Removes logical index i, shifting the following elements one step back. */
    private E delete(int i){E e=at(i);if(i==0){a[head]=null;head=slot(1);}else{for(;i<n-1;i++)a[slot(i)]=a[slot(i+1)];a[slot(i)]=null;}n--;mods++;return e;}
    public void clear(){for(int i=0;i<n;i++)a[slot(i)]=null;n=head=0;mods++;}
    public Iterator<E> iterator(){return new Cursor(false);}
    public Iterator<E> descendingIterator(){return new Cursor(true);}
    private final class Cursor implements Iterator<E> {
        final boolean down;int next,last=-1,expected=mods;
        Cursor(boolean down){this.down=down;next=down?n-1:0;}
        public boolean hasNext(){return down?next>=0:next<n;}
        public E next(){if(expected!=mods)throw new ConcurrentModificationException();if(!hasNext())throw new NoSuchElementException();last=next;next+=down?-1:1;return at(last);}
        public void remove(){if(last<0)throw new IllegalStateException();if(expected!=mods)throw new ConcurrentModificationException();delete(last);if(!down)next=last;last=-1;expected=mods;}
    }
    public ArrayDeque<E> clone(){return new ArrayDeque<E>(this);}
    /** Reverse-ordered view returned by Deque.reversed(). */
    static final class Reversed<E> extends AbstractCollection<E> implements Deque<E> {
        final Deque<E> d;
        Reversed(Deque<E> d){this.d=d;}
        public int size(){return d.size();}
        public Iterator<E> iterator(){return d.descendingIterator();}
        public Iterator<E> descendingIterator(){return d.iterator();}
        public boolean add(E e){d.addFirst(e);return true;}
        public void addFirst(E e){d.addLast(e);}
        public void addLast(E e){d.addFirst(e);}
        public E pollFirst(){return d.pollLast();}
        public E pollLast(){return d.pollFirst();}
        public E peekFirst(){return d.peekLast();}
        public E peekLast(){return d.peekFirst();}
        public Deque<E> reversed(){return d;}
    }
}
