package java.util;
import java.util.function.Predicate;
/** Binary heap with the JDK's exact sift steps, so array (iteration) order matches HotSpot. */
@SuppressWarnings("unchecked")
public class PriorityQueue<E> extends AbstractQueue<E> implements java.io.Serializable {
    private Object[] queue;private int size,modCount;private final Comparator<? super E> comparator;
    public PriorityQueue(){this(11,null);}
    public PriorityQueue(int capacity){this(capacity,null);}
    public PriorityQueue(Comparator<? super E> comparator){this(11,comparator);}
    public PriorityQueue(int capacity,Comparator<? super E> comparator){if(capacity<1)throw new IllegalArgumentException();queue=new Object[capacity];this.comparator=comparator;}
    public PriorityQueue(PriorityQueue<? extends E> c){this((Collection<? extends E>)c);}
    public PriorityQueue(SortedSet<? extends E> c){this((Collection<? extends E>)c);}
    public PriorityQueue(Collection<? extends E> c){
        // Sorted sets and heaps already satisfy the heap invariant, so heapify keeps their order.
        comparator=c instanceof SortedSet<?>?((SortedSet<E>)c).comparator():c instanceof PriorityQueue<?>?((PriorityQueue<E>)c).comparator:null;
        queue=c.toArray(new Object[0]);size=queue.length;for(Object e:queue)Objects.requireNonNull(e);
        heapify();
    }
    private int cmp(Object a,Object b){return comparator==null?((Comparable<Object>)a).compareTo(b):comparator.compare((E)a,(E)b);}
    private void siftUp(int k,Object x){
        if(comparator==null){Comparable<?> key=(Comparable<?>)x;}
        while(k>0){int p=(k-1)>>>1;Object e=queue[p];if(cmp(x,e)>=0)break;queue[k]=e;k=p;}
        queue[k]=x;
    }
    private void siftDown(int k,Object x){
        if(comparator==null){Comparable<?> key=(Comparable<?>)x;}
        int n=size,half=n>>>1;
        while(k<half){int child=2*k+1,right=child+1;Object c=queue[child];if(right<n&&cmp(c,queue[right])>0)c=queue[child=right];if(cmp(x,c)<=0)break;queue[k]=c;k=child;}
        queue[k]=x;
    }
    private void heapify(){for(int i=(size>>>1)-1;i>=0;i--)siftDown(i,queue[i]);}
    public boolean offer(E e){
        Objects.requireNonNull(e);modCount++;int i=size;
        if(i>=queue.length)queue=Arrays.copyOf(queue,i+(i<64?i+2:i>>1));
        siftUp(i,e);size=i+1;return true;
    }
    public E peek(){return size==0?null:(E)queue[0];}
    public E poll(){if(size==0)return null;E r=(E)queue[0];modCount++;int n=--size;Object x=queue[n];queue[n]=null;if(n>0)siftDown(0,x);return r;}
    /** Returns the last element if it moved to before index i (an iterator must still visit it), else null. */
    private E removeAt(int i){
        modCount++;int s=--size;
        if(s==i)queue[i]=null;
        else{Object moved=queue[s];queue[s]=null;siftDown(i,moved);if(queue[i]==moved){siftUp(i,moved);if(queue[i]!=moved)return (E)moved;}}
        return null;
    }
    private int indexOf(Object o){if(o!=null)for(int i=0;i<size;i++)if(o.equals(queue[i]))return i;return -1;}
    public boolean contains(Object o){return indexOf(o)>=0;}
    public boolean remove(Object o){int i=indexOf(o);if(i<0)return false;removeAt(i);return true;}
    public int size(){return size;}
    public void clear(){modCount++;for(int i=0;i<size;i++)queue[i]=null;size=0;}
    public Comparator<? super E> comparator(){return comparator;}
    public Object[] toArray(){return Arrays.copyOf(queue,size);}
    public boolean removeIf(Predicate<? super E> filter){return bulk(null,false,Objects.requireNonNull(filter));}
    public boolean removeAll(Collection<?> c){return bulk(Objects.requireNonNull(c),true,null);}
    public boolean retainAll(Collection<?> c){return bulk(Objects.requireNonNull(c),false,null);}
    /** JDK bulkRemove: test every element, compact survivors in array order, then heapify. */
    private boolean bulk(Collection<?> c,boolean in,Predicate<? super E> filter){
        int expected=++modCount,end=size,w=0;Object[] es=queue;boolean[] dead=new boolean[end];
        for(int i=0;i<end;i++)dead[i]=filter!=null?filter.test((E)es[i]):c.contains(es[i])==in;
        if(modCount!=expected)throw new ConcurrentModificationException();
        for(int i=0;i<end;i++)if(!dead[i])es[w++]=es[i];
        if(w==end)return false;
        for(int i=size=w;i<end;i++)es[i]=null;
        heapify();return true;
    }
    public Iterator<E> iterator(){return new Iterator<E>(){
        int cursor,lastRet=-1,expected=modCount;ArrayDeque<E> forgetMeNot;E lastRetElt;
        public boolean hasNext(){return cursor<size||(forgetMeNot!=null&&!forgetMeNot.isEmpty());}
        public E next(){
            if(expected!=modCount)throw new ConcurrentModificationException();
            if(cursor<size)return (E)queue[lastRet=cursor++];
            if(forgetMeNot!=null){lastRet=-1;lastRetElt=forgetMeNot.poll();if(lastRetElt!=null)return lastRetElt;}
            throw new NoSuchElementException();
        }
        public void remove(){
            if(expected!=modCount)throw new ConcurrentModificationException();
            if(lastRet!=-1){E moved=removeAt(lastRet);lastRet=-1;if(moved==null)cursor--;else{if(forgetMeNot==null)forgetMeNot=new ArrayDeque<E>();forgetMeNot.add(moved);}}
            else if(lastRetElt!=null){for(int i=0;i<size;i++)if(queue[i]==lastRetElt){removeAt(i);break;}lastRetElt=null;}
            else throw new IllegalStateException();
            expected=modCount;
        }
    };}
}
