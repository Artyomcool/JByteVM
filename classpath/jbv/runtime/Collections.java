package jbv.runtime;
import java.util.*;
public final class Collections {
    private Collections() {}
    @SuppressWarnings({"unchecked","rawtypes"}) private static int compare(Object a,Object b,Comparator comparator){return comparator==null?((Comparable)a).compareTo(b):comparator.compare(a,b);}
    public static void sort(Object[] values,Comparator<?> comparator){
        int n=values.length;if(n<2)return;Object[] scratch=new Object[n];Object[] from=values,to=scratch;
        for(int width=1;width<n;width=width>n/2?n:width*2){
            for(int start=0;start<n;){int mid=start+Math.min(width,n-start),end=mid+Math.min(width,n-mid),a=start,b=mid;
                for(int i=start;i<end;i++)to[i]=(b==end||(a<mid&&compare(from[a],from[b],comparator)<=0))?from[a++]:from[b++];start=end;}
            Object[] swap=from;from=to;to=swap;
        }
        if(from!=values)System.arraycopy(from,0,values,0,n);
    }
    public static <E> List<E> immutableList(Object[] values){return new FrozenList<E>(values);}
    public static <E> Set<E> immutableSet(Object[] values){HashSet<E> set=new HashSet<E>();for(Object x:values){@SuppressWarnings("unchecked") E e=(E)Objects.requireNonNull(x);if(!set.add(e))throw new IllegalArgumentException();}return new FrozenSet<E>(set);}
    public static final class FrozenList<E> extends AbstractList<E> implements RandomAccess {
        private final Object[] values;
        public FrozenList(Object[] source){values=new Object[source.length];for(int i=0;i<values.length;i++)values[i]=Objects.requireNonNull(source[i]);}
        public int size(){return values.length;}
        @SuppressWarnings("unchecked") public E get(int i){return (E)values[Objects.checkIndex(i,values.length)];}
        public void clear(){throw new UnsupportedOperationException();}
        public boolean remove(Object value){throw new UnsupportedOperationException();}
        public boolean removeAll(Collection<?> c){throw new UnsupportedOperationException();}
        public boolean retainAll(Collection<?> c){throw new UnsupportedOperationException();}
        public boolean removeIf(java.util.function.Predicate<? super E> p){throw new UnsupportedOperationException();}
        public boolean addAll(Collection<? extends E> c){throw new UnsupportedOperationException();}
        public boolean addAll(int i,Collection<? extends E> c){throw new UnsupportedOperationException();}
        public void replaceAll(java.util.function.UnaryOperator<E> p){throw new UnsupportedOperationException();}
        public void sort(Comparator<? super E> c){throw new UnsupportedOperationException();}
    }
    public static final class FrozenSet<E> extends AbstractSet<E> {
        private final Set<E> set;
        public FrozenSet(Set<E> set){this.set=set;}
        public int size(){return set.size();}
        public boolean contains(Object x){return set.contains(x);}
        public Iterator<E> iterator(){Iterator<E> it=set.iterator();return new Iterator<E>(){public boolean hasNext(){return it.hasNext();}public E next(){return it.next();}};}
        public void clear(){throw new UnsupportedOperationException();}
        public boolean remove(Object x){throw new UnsupportedOperationException();}
        public boolean removeAll(Collection<?> c){throw new UnsupportedOperationException();}
        public boolean retainAll(Collection<?> c){throw new UnsupportedOperationException();}
        public boolean removeIf(java.util.function.Predicate<? super E> p){throw new UnsupportedOperationException();}
        public boolean addAll(Collection<? extends E> c){throw new UnsupportedOperationException();}
    }
    public static final class FrozenMap<K,V> extends AbstractMap<K,V> {
        private final Map<K,V> map;
        public FrozenMap(Map<K,V> map){this.map=map;}
        public int size(){return map.size();}
        public V get(Object key){return map.get(key);}
        public boolean containsKey(Object key){return map.containsKey(key);}
        public Set<Entry<K,V>> entrySet(){return new AbstractSet<Entry<K,V>>(){
            public int size(){return map.size();}
            public Iterator<Entry<K,V>> iterator(){Iterator<Entry<K,V>> it=map.entrySet().iterator();return new Iterator<Entry<K,V>>(){public boolean hasNext(){return it.hasNext();}public Entry<K,V> next(){return new SimpleImmutableEntry<K,V>(it.next());}};}
        };}
        public V remove(Object key){throw new UnsupportedOperationException();}
        public void clear(){throw new UnsupportedOperationException();}
        public void putAll(Map<? extends K,? extends V> m){throw new UnsupportedOperationException();}
        public V putIfAbsent(K k,V v){throw new UnsupportedOperationException();}
        public boolean remove(Object k,Object v){throw new UnsupportedOperationException();}
        public boolean replace(K k,V a,V b){throw new UnsupportedOperationException();}
        public V replace(K k,V v){throw new UnsupportedOperationException();}
        public void replaceAll(java.util.function.BiFunction<? super K,? super V,? extends V> f){throw new UnsupportedOperationException();}
        public V compute(K k,java.util.function.BiFunction<? super K,? super V,? extends V> f){throw new UnsupportedOperationException();}
        public V computeIfAbsent(K k,java.util.function.Function<? super K,? extends V> f){throw new UnsupportedOperationException();}
        public V computeIfPresent(K k,java.util.function.BiFunction<? super K,? super V,? extends V> f){throw new UnsupportedOperationException();}
        public V merge(K k,V v,java.util.function.BiFunction<? super V,? super V,? extends V> f){throw new UnsupportedOperationException();}
    }
    public static final class ReverseList<E> extends AbstractList<E> {
        private final List<E> list;
        public ReverseList(List<E> list){this.list=list;}
        public int size(){return list.size();}
        public E get(int i){return list.get(size()-1-Objects.checkIndex(i,size()));}
        public E set(int i,E e){return list.set(size()-1-Objects.checkIndex(i,size()),e);}
        public void add(int i,E e){position(i);list.add(size()-i,e);}
        public E remove(int i){return list.remove(size()-1-Objects.checkIndex(i,size()));}
        public List<E> reversed(){return list;}
        public List<E> subList(int from,int to){if(from>to)throw new IllegalArgumentException();Objects.checkFromToIndex(from,to,size());return list.subList(size()-to,size()-from).reversed();}
        public ListIterator<E> listIterator(int index){position(index);ListIterator<E> it=list.listIterator(size()-index);return new ListIterator<E>(){
            boolean writable;
            public boolean hasNext(){return it.hasPrevious();}public boolean hasPrevious(){return it.hasNext();}
            public E next(){E e=it.previous();writable=true;return e;}public E previous(){E e=it.next();writable=true;return e;}
            public int nextIndex(){return size()-it.nextIndex();}public int previousIndex(){return nextIndex()-1;}
            public void remove(){if(!writable)throw new IllegalStateException();it.remove();writable=false;}public void set(E e){if(!writable)throw new IllegalStateException();it.set(e);}public void add(E e){it.add(e);it.previous();writable=false;}
        };}
    }
}
