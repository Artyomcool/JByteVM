package java.util;
public abstract class AbstractCollection<E> implements Collection<E> {
    protected AbstractCollection() {}
    public abstract Iterator<E> iterator(); public abstract int size();
    public boolean isEmpty() {return size()==0;}
    public boolean contains(Object value) {for(E x:this)if(Objects.equals(value,x))return true;return false;}
    public Object[] toArray() {return toArray(new Object[size()]);}
    @SuppressWarnings("unchecked") public <T> T[] toArray(T[] target) {
        int n=size();if(target.length<n)target=(T[])jbv.runtime.Support.newArrayLike(target,n);
        int i=0;for(E x:this)target[i++]=(T)x;if(target.length>i)target[i]=null;return target;
    }
    public boolean add(E value) {throw new UnsupportedOperationException();}
    public boolean remove(Object value) {Iterator<E> it=iterator();while(it.hasNext())if(Objects.equals(value,it.next())){it.remove();return true;}return false;}
    public boolean containsAll(Collection<?> other) {for(Object x:other)if(!contains(x))return false;return true;}
    public boolean addAll(Collection<? extends E> other) {boolean changed=false;for(E x:other)changed|=add(x);return changed;}
    public boolean removeAll(Collection<?> other) {Objects.requireNonNull(other);boolean changed=false;Iterator<E> it=iterator();while(it.hasNext())if(other.contains(it.next())){it.remove();changed=true;}return changed;}
    public boolean retainAll(Collection<?> other) {Objects.requireNonNull(other);boolean changed=false;Iterator<E> it=iterator();while(it.hasNext())if(!other.contains(it.next())){it.remove();changed=true;}return changed;}
    public void clear() {Iterator<E> it=iterator();while(it.hasNext()){it.next();it.remove();}}
    public String toString() {StringBuilder b=new StringBuilder("[");boolean first=true;for(E x:this){if(!first)b.append(", ");first=false;b.append(x==this?"(this Collection)":x);}return b.append(']').toString();}
}
