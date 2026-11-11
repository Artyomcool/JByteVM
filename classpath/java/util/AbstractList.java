package java.util;
public abstract class AbstractList<E> extends AbstractCollection<E> implements List<E> {
    protected transient int modCount;
    protected AbstractList() {}
    public abstract E get(int index);
    protected void position(int index) {if(index<0||index>size())throw new IndexOutOfBoundsException();}
    public E set(int index,E value) {throw new UnsupportedOperationException();}
    public void add(int index,E value) {throw new UnsupportedOperationException();}
    public E remove(int index) {throw new UnsupportedOperationException();}
    public boolean add(E value) {add(size(),value);return true;}
    public boolean addAll(int index,Collection<? extends E> other) {position(index);boolean changed=false;for(E x:other){add(index++,x);changed=true;}return changed;}
    public int indexOf(Object value) {ListIterator<E> it=listIterator();while(it.hasNext())if(Objects.equals(value,it.next()))return it.previousIndex();return -1;}
    public int lastIndexOf(Object value) {ListIterator<E> it=listIterator(size());while(it.hasPrevious())if(Objects.equals(value,it.previous()))return it.nextIndex();return -1;}
    public void clear() {removeRange(0,size());}
    protected void removeRange(int from,int to) {ListIterator<E> it=listIterator(from);for(int i=from;i<to;i++){it.next();it.remove();}}
    public Iterator<E> iterator() {return listIterator();}
    public ListIterator<E> listIterator() {return listIterator(0);}
    public ListIterator<E> listIterator(int index) {position(index);return new Cursor(index);}
    private final class Cursor implements ListIterator<E> {
        int next,last=-1,expected=modCount;
        Cursor(int index){next=index;}
        void check(){if(expected!=modCount)throw new ConcurrentModificationException();}
        public boolean hasNext(){return next<size();}
        public boolean hasPrevious(){return next>0;}
        public int nextIndex(){return next;}
        public int previousIndex(){return next-1;}
        public E next(){check();if(!hasNext())throw new NoSuchElementException();E x=get(next);last=next++;return x;}
        public E previous(){check();if(!hasPrevious())throw new NoSuchElementException();E x=get(next-1);last=--next;return x;}
        public void remove(){if(last<0)throw new IllegalStateException();check();AbstractList.this.remove(last);if(last<next)next--;last=-1;expected=modCount;}
        public void set(E value){if(last<0)throw new IllegalStateException();check();AbstractList.this.set(last,value);}
        public void add(E value){check();AbstractList.this.add(next,value);next++;last=-1;expected=modCount;}
    }
    public boolean equals(Object other) {if(other==this)return true;if(!(other instanceof List<?>))return false;Iterator<?> b=((List<?>)other).iterator();for(E a:this)if(!b.hasNext()||!Objects.equals(a,b.next()))return false;return !b.hasNext();}
    public int hashCode(){int h=1;for(E x:this)h=31*h+Objects.hashCode(x);return h;}
    public List<E> subList(int from,int to){if(from>to)throw new IllegalArgumentException();Objects.checkFromToIndex(from,to,size());return this instanceof RandomAccess?new RandomSubList<E>(this,null,from,to-from):new SubList<E>(this,null,from,to-from);}
    private static class SubList<E> extends AbstractList<E> {
        final AbstractList<E> root;final SubList<E> parent;final int offset;int length;
        SubList(AbstractList<E> root,SubList<E> parent,int offset,int length){this.root=root;this.parent=parent;this.offset=offset;this.length=length;modCount=root.modCount;}
        void check(){if(modCount!=root.modCount)throw new ConcurrentModificationException();}
        void updated(int n){for(SubList<E> s=this;s!=null;s=s.parent){s.length+=n;s.modCount=root.modCount;}}
        public int size(){check();return length;}
        public E get(int i){Objects.checkIndex(i,size());return root.get(offset+i);}
        public E set(int i,E x){Objects.checkIndex(i,size());return root.set(offset+i,x);}
        public void add(int i,E x){position(i);root.add(offset+i,x);updated(1);}
        public E remove(int i){Objects.checkIndex(i,size());E x=root.remove(offset+i);updated(-1);return x;}
        protected void removeRange(int from,int to){Objects.checkFromToIndex(from,to,size());root.removeRange(offset+from,offset+to);updated(from-to);}
        public boolean addAll(int i,Collection<? extends E> c){position(i);int n=c.size();boolean changed=root.addAll(offset+i,c);updated(n);return changed;}
        public List<E> subList(int from,int to){if(from>to)throw new IllegalArgumentException();Objects.checkFromToIndex(from,to,size());return this instanceof RandomAccess?new RandomSubList<E>(root,this,offset+from,to-from):new SubList<E>(root,this,offset+from,to-from);}
    }
    private static final class RandomSubList<E> extends SubList<E> implements RandomAccess {
        RandomSubList(AbstractList<E> root,SubList<E> parent,int offset,int length){super(root,parent,offset,length);}
    }
}
