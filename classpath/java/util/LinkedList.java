package java.util;
/**
 * Circular doubly linked list around a sentinel. reversed() returns a LinkedList sharing the
 * sentinel with the direction flipped; size and modCount always live in the original (base).
 */
public class LinkedList<E> extends AbstractList<E> implements List<E>,Deque<E>,Cloneable,java.io.Serializable {
    private static final class Node<E> {E item;Node<E> next,prev;Node(E item){this.item=item;}}
    private final Node<E> head;private final LinkedList<E> base;private final boolean rev;private int size;
    public LinkedList(){head=new Node<E>(null);head.next=head.prev=head;base=this;rev=false;}
    public LinkedList(Collection<? extends E> c){this();addAll(c);}
    private LinkedList(LinkedList<E> b){head=b.head;base=b;rev=true;}
    private Node<E> step(Node<E> n,boolean forward){return forward!=rev?n.next:n.prev;}
    private Node<E> node(int i){
        int n=size();Node<E> x=head;
        if(i<n>>1)for(int k=0;k<=i;k++)x=step(x,true);else for(int k=n;k>i;k--)x=step(x,false);
        return x;
    }
    private Node<E> linkBefore(E e,Node<E> s){
        Node<E> p=step(s,false),x=new Node<E>(e),a=rev?s:p,b=rev?p:s;
        x.prev=a;x.next=b;a.next=x;b.prev=x;base.size++;base.modCount++;return x;
    }
    private E unlink(Node<E> n){n.prev.next=n.next;n.next.prev=n.prev;base.size--;base.modCount++;return n.item;}
    public int size(){return base.size;}
    public E get(int i){Objects.checkIndex(i,size());return node(i).item;}
    public E set(int i,E e){Objects.checkIndex(i,size());Node<E> n=node(i);E old=n.item;n.item=e;return old;}
    public void add(int i,E e){position(i);linkBefore(e,i==size()?head:node(i));}
    public boolean add(E e){linkBefore(e,head);return true;}
    public E remove(int i){Objects.checkIndex(i,size());return unlink(node(i));}
    public void clear(){head.next=head.prev=head;base.size=0;base.modCount++;}
    public void addFirst(E e){linkBefore(e,step(head,true));}
    public void addLast(E e){linkBefore(e,head);}
    public E peekFirst(){return step(head,true).item;}
    public E peekLast(){return step(head,false).item;}
    public E pollFirst(){return size()==0?null:unlink(step(head,true));}
    public E pollLast(){return size()==0?null:unlink(step(head,false));}
    public E getFirst(){return Deque.super.getFirst();}
    public E getLast(){return Deque.super.getLast();}
    public E removeFirst(){return Deque.super.removeFirst();}
    public E removeLast(){return Deque.super.removeLast();}
    public LinkedList<E> reversed(){return rev?base:new LinkedList<E>(this);}
    public Iterator<E> descendingIterator(){return reversed().iterator();}
    /** A reversed view's sublists are reversed sublists of the base, so they see the base's modCount. */
    public List<E> subList(int from,int to){if(!rev)return super.subList(from,to);int n=size();Objects.checkFromToIndex(from,to,n);return base.subList(n-to,n-from).reversed();}
    public ListIterator<E> listIterator(int index){position(index);return new Cursor(index);}
    private final class Cursor implements ListIterator<E> {
        Node<E> next,last;int index,expected=base.modCount;
        Cursor(int i){index=i;next=i==size()?head:node(i);}
        void check(){if(expected!=base.modCount)throw new ConcurrentModificationException();}
        public boolean hasNext(){return index<size();}
        public boolean hasPrevious(){return index>0;}
        public int nextIndex(){return index;}
        public int previousIndex(){return index-1;}
        public E next(){check();if(!hasNext())throw new NoSuchElementException();last=next;next=step(next,true);index++;return last.item;}
        public E previous(){check();if(!hasPrevious())throw new NoSuchElementException();next=last=step(next,false);index--;return last.item;}
        public void remove(){check();if(last==null)throw new IllegalStateException();Node<E> after=step(last,true);unlink(last);if(next==last)next=after;else index--;last=null;expected=base.modCount;}
        public void set(E e){if(last==null)throw new IllegalStateException();check();last.item=e;}
        // Like the JDK reverse view (add, then previous), a reversed view reports the added element as last returned.
        public void add(E e){check();Node<E> x=linkBefore(e,next);last=rev?x:null;index++;expected=base.modCount;}
    }
    public Object clone(){return new LinkedList<E>(this);}
}
