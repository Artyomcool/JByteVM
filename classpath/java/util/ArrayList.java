package java.util;
public class ArrayList<E> extends AbstractList<E> implements RandomAccess,Cloneable,java.io.Serializable {
    private Object[] values;private int length;
    public ArrayList(){values=new Object[0];}
    public ArrayList(int capacity){if(capacity<0)throw new IllegalArgumentException();values=new Object[capacity];}
    public ArrayList(Collection<? extends E> other){values=other.toArray();length=values.length;}
    public int size(){return length;}
    private void grow(int required){if(required<0)throw new OutOfMemoryError();if(required>values.length){int n=values.length+Math.max(1,values.length/2);if(n<required)n=required;Object[] next=new Object[n];System.arraycopy(values,0,next,0,length);values=next;}}
    public void ensureCapacity(int capacity){if(capacity>values.length){grow(capacity);modCount++;}}
    public void trimToSize(){modCount++;if(length<values.length){Object[] next=new Object[length];System.arraycopy(values,0,next,0,length);values=next;}}
    @SuppressWarnings("unchecked") public E get(int index){Objects.checkIndex(index,length);return (E)values[index];}
    @SuppressWarnings("unchecked") public E set(int index,E value){Objects.checkIndex(index,length);E old=(E)values[index];values[index]=value;return old;}
    public void add(int index,E value){position(index);grow(length+1);System.arraycopy(values,index,values,index+1,length-index);values[index]=value;length++;modCount++;}
    public boolean addAll(Collection<? extends E> other){return addAll(length,other);}
    public boolean addAll(int index,Collection<? extends E> other){position(index);Object[] a=other.toArray();modCount++;if(a.length==0)return false;grow(length+a.length);System.arraycopy(values,index,values,index+a.length,length-index);System.arraycopy(a,0,values,index,a.length);length+=a.length;return true;}
    @SuppressWarnings("unchecked") public E remove(int index){Objects.checkIndex(index,length);E old=(E)values[index];removeRange(index,index+1);return old;}
    protected void removeRange(int from,int to){Objects.checkFromToIndex(from,to,length);int n=to-from;System.arraycopy(values,to,values,from,length-to);for(int i=length-n;i<length;i++)values[i]=null;length-=n;modCount++;}
    public Object[] toArray(){Object[] a=new Object[length];System.arraycopy(values,0,a,0,length);return a;}
    @SuppressWarnings("unchecked") public <T> T[] toArray(T[] target){if(target.length<length)target=(T[])jbv.runtime.Support.newArrayLike(target,length);System.arraycopy(values,0,target,0,length);if(target.length>length)target[length]=null;return target;}
    public Object clone(){return new ArrayList<E>(this);}
}
