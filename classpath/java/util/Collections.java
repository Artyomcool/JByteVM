package java.util;
import java.util.function.*;
/** java.util.Collections: algorithms, read-only views, empty/singleton/nCopies. */
public final class Collections {
    private Collections() {}
    @SuppressWarnings("rawtypes") public static final List EMPTY_LIST=new View<Object>(new ArrayList<Object>(0));
    @SuppressWarnings("rawtypes") public static final Set EMPTY_SET=new ViewSet<Object>(new HashSet<Object>());
    @SuppressWarnings("rawtypes") public static final Map EMPTY_MAP=new ViewMap<Object,Object>(new HashMap<Object,Object>());
    static UnsupportedOperationException readOnly(){return new UnsupportedOperationException();}

    public static <T extends Comparable<? super T>> void sort(List<T> list){list.sort(null);}
    public static <T> void sort(List<T> list,Comparator<? super T> c){list.sort(c);}
    public static <T> int binarySearch(List<? extends Comparable<? super T>> list,T key){return binarySearch0(list,key,null);}
    @SuppressWarnings("unchecked") public static <T> int binarySearch(List<? extends T> list,T key,Comparator<? super T> c){return binarySearch0(list,key,(Comparator<Object>)c);}
    @SuppressWarnings({"unchecked","rawtypes"}) private static int binarySearch0(List<?> list,Object key,Comparator<Object> c){
        int lo=0,hi=list.size()-1;
        while(lo<=hi){int mid=(lo+hi)>>>1;Object v=list.get(mid);int r=c==null?((Comparable)v).compareTo(key):c.compare(v,key);if(r<0)lo=mid+1;else if(r>0)hi=mid-1;else return mid;}
        return -(lo+1);
    }
    public static void reverse(List<?> list){swapRange(list,0,list.size());}
    @SuppressWarnings({"unchecked","rawtypes"}) private static void swapRange(List list,int from,int to){for(int i=from,j=to-1;i<j;i++,j--)list.set(i,list.set(j,list.get(i)));}
    @SuppressWarnings({"unchecked","rawtypes"}) public static void swap(List<?> list,int i,int j){List l=list;l.set(i,l.set(j,l.get(i)));}
    public static void shuffle(List<?> list){shuffle(list,new Random());}
    public static void shuffle(List<?> list,Random random){for(int i=list.size();i>1;i--)swap(list,i-1,random.nextInt(i));}
    public static <T> void fill(List<? super T> list,T value){for(int i=0,n=list.size();i<n;i++)list.set(i,value);}
    public static <T> void copy(List<? super T> to,List<? extends T> from){int n=from.size();if(n>to.size())throw new IndexOutOfBoundsException("Source does not fit in dest");for(int i=0;i<n;i++)to.set(i,from.get(i));}
    public static void rotate(List<?> list,int distance){int n=list.size();if(n==0)return;distance%=n;if(distance<0)distance+=n;if(distance==0)return;swapRange(list,0,n);swapRange(list,0,distance);swapRange(list,distance,n);}
    public static <T> boolean replaceAll(List<T> list,T from,T to){boolean any=false;for(int i=0,n=list.size();i<n;i++)if(Objects.equals(list.get(i),from)){list.set(i,to);any=true;}return any;}
    public static int indexOfSubList(List<?> source,List<?> target){int n=source.size(),m=target.size();for(int i=0;i+m<=n;i++){int j=0;while(j<m&&Objects.equals(source.get(i+j),target.get(j)))j++;if(j==m)return i;}return -1;}
    public static int lastIndexOfSubList(List<?> source,List<?> target){int n=source.size(),m=target.size();for(int i=n-m;i>=0;i--){int j=0;while(j<m&&Objects.equals(source.get(i+j),target.get(j)))j++;if(j==m)return i;}return -1;}
    public static <T extends Object & Comparable<? super T>> T min(Collection<? extends T> c){return extreme(c,null,-1);}
    public static <T> T min(Collection<? extends T> c,Comparator<? super T> cmp){return extreme(c,cmp,-1);}
    public static <T extends Object & Comparable<? super T>> T max(Collection<? extends T> c){return extreme(c,null,1);}
    public static <T> T max(Collection<? extends T> c,Comparator<? super T> cmp){return extreme(c,cmp,1);}
    @SuppressWarnings({"unchecked","rawtypes"}) private static <T> T extreme(Collection<? extends T> c,Comparator<? super T> cmp,int sign){
        Iterator<? extends T> it=c.iterator();T best=it.next();
        while(it.hasNext()){T x=it.next();int r=cmp==null?((Comparable)x).compareTo(best):cmp.compare(x,best);if(r*sign>0)best=x;}
        return best;
    }
    public static int frequency(Collection<?> c,Object o){int n=0;for(Object x:c)if(Objects.equals(o,x))n++;return n;}
    public static boolean disjoint(Collection<?> a,Collection<?> b){for(Object x:a)if(b.contains(x))return false;return true;}
    @SafeVarargs public static <T> boolean addAll(Collection<? super T> c,T... values){boolean any=false;for(T x:values)any|=c.add(x);return any;}
    @SuppressWarnings("unchecked") public static <T> Comparator<T> reverseOrder(){return (Comparator<T>)REVERSE;}
    public static <T> Comparator<T> reverseOrder(Comparator<T> c){if(c==null)return reverseOrder();Comparator<T> self=c;return new Comparator<T>(){public int compare(T a,T b){return self.compare(b,a);}};}
    @SuppressWarnings({"unchecked","rawtypes"}) private static final Comparator<Object> REVERSE=new Comparator<Object>(){public int compare(Object a,Object b){return ((Comparable)b).compareTo(a);}};

    @SuppressWarnings("unchecked") public static <T> List<T> emptyList(){return (List<T>)EMPTY_LIST;}
    @SuppressWarnings("unchecked") public static <T> Set<T> emptySet(){return (Set<T>)EMPTY_SET;}
    @SuppressWarnings("unchecked") public static <K,V> Map<K,V> emptyMap(){return (Map<K,V>)EMPTY_MAP;}
    public static <T> Iterator<T> emptyIterator(){return Collections.<T>emptyList().iterator();}
    public static <T> List<T> singletonList(T value){ArrayList<T> a=new ArrayList<T>(1);a.add(value);return new View<T>(a);}
    public static <T> Set<T> singleton(T value){HashSet<T> a=new HashSet<T>();a.add(value);return new ViewSet<T>(a);}
    public static <K,V> Map<K,V> singletonMap(K key,V value){HashMap<K,V> a=new HashMap<K,V>();a.put(key,value);return new ViewMap<K,V>(a);}
    public static <T> List<T> nCopies(int n,T value){
        if(n<0)throw new IllegalArgumentException("List length = "+n);
        return new View<T>(new AbstractList<T>(){public int size(){return n;}public T get(int i){Objects.checkIndex(i,n);return value;}});
    }
    @SuppressWarnings("unchecked") public static <T> Collection<T> unmodifiableCollection(Collection<? extends T> c){return c instanceof ViewCollection?(Collection<T>)c:new ViewCollection<T>(c);}
    @SuppressWarnings("unchecked") public static <T> List<T> unmodifiableList(List<? extends T> list){return list instanceof View?(List<T>)list:new View<T>(list);}
    @SuppressWarnings("unchecked") public static <T> Set<T> unmodifiableSet(Set<? extends T> set){return set instanceof ViewSet?(Set<T>)set:new ViewSet<T>(set);}
    @SuppressWarnings("unchecked") public static <K,V> Map<K,V> unmodifiableMap(Map<? extends K,? extends V> map){return map instanceof ViewMap?(Map<K,V>)map:new ViewMap<K,V>(map);}

    /** Read-only iterator over a backing collection. */
    static <E> Iterator<E> readOnly(Iterator<? extends E> it){return new Iterator<E>(){public boolean hasNext(){return it.hasNext();}public E next(){return it.next();}};}
    static class ViewCollection<E> extends AbstractCollection<E> {
        final Collection<? extends E> c;
        ViewCollection(Collection<? extends E> c){this.c=Objects.requireNonNull(c);}
        public int size(){return c.size();}
        public boolean contains(Object o){return c.contains(o);}
        public boolean containsAll(Collection<?> o){return c.containsAll(o);}
        public Iterator<E> iterator(){return readOnly(c.iterator());}
        public Object[] toArray(){return c.toArray();}
        public <T> T[] toArray(T[] a){return c.toArray(a);}
        public String toString(){return c.toString();}
        public boolean add(E e){throw readOnly();}
        public boolean remove(Object o){throw readOnly();}
        public boolean addAll(Collection<? extends E> o){throw readOnly();}
        public boolean removeAll(Collection<?> o){throw readOnly();}
        public boolean retainAll(Collection<?> o){throw readOnly();}
        public boolean removeIf(Predicate<? super E> p){throw readOnly();}
        public void clear(){throw readOnly();}
    }
    static final class ViewSet<E> extends ViewCollection<E> implements Set<E> {
        ViewSet(Set<? extends E> s){super(s);}
        public boolean equals(Object o){return o==this||c.equals(o);}
        public int hashCode(){return c.hashCode();}
    }
    /** Read-only list view; positional access and list iterators come from AbstractList. */
    static final class View<E> extends AbstractList<E> implements RandomAccess {
        final List<? extends E> list;
        View(List<? extends E> list){this.list=Objects.requireNonNull(list);}
        public int size(){return list.size();}
        public E get(int i){return list.get(i);}
        public boolean contains(Object o){return list.contains(o);}
        public int indexOf(Object o){return list.indexOf(o);}
        public int lastIndexOf(Object o){return list.lastIndexOf(o);}
        public boolean equals(Object o){return o==this||list.equals(o);}
        public int hashCode(){return list.hashCode();}
        public List<E> subList(int from,int to){return new View<E>(list.subList(from,to));}
        public Iterator<E> iterator(){return readOnly(list.iterator());}
        public ListIterator<E> listIterator(){return listIterator(0);}
        public ListIterator<E> listIterator(int index){
            ListIterator<? extends E> it=list.listIterator(index);
            return new ListIterator<E>(){
                public boolean hasNext(){return it.hasNext();} public E next(){return it.next();}
                public boolean hasPrevious(){return it.hasPrevious();} public E previous(){return it.previous();}
                public int nextIndex(){return it.nextIndex();} public int previousIndex(){return it.previousIndex();}
                public void remove(){throw readOnly();} public void set(E e){throw readOnly();} public void add(E e){throw readOnly();}
            };
        }
        public void clear(){throw readOnly();}
        public boolean removeIf(Predicate<? super E> p){throw readOnly();}
        public void replaceAll(UnaryOperator<E> op){throw readOnly();}
        public void sort(Comparator<? super E> c){throw readOnly();}
        public boolean addAll(Collection<? extends E> o){throw readOnly();}
        public boolean removeAll(Collection<?> o){throw readOnly();}
        public boolean retainAll(Collection<?> o){throw readOnly();}
    }
    static final class ViewMap<K,V> extends AbstractMap<K,V> {
        final Map<? extends K,? extends V> map;
        ViewMap(Map<? extends K,? extends V> map){this.map=Objects.requireNonNull(map);}
        public int size(){return map.size();}
        public V get(Object key){return map.get(key);}
        public boolean containsKey(Object key){return map.containsKey(key);}
        public boolean containsValue(Object value){return map.containsValue(value);}
        public boolean equals(Object o){return o==this||map.equals(o);}
        public int hashCode(){return map.hashCode();}
        public Set<Entry<K,V>> entrySet(){
            Set<? extends Entry<? extends K,? extends V>> entries=map.entrySet();
            return new ViewSet<Entry<K,V>>(new AbstractSet<Entry<K,V>>(){
                public int size(){return entries.size();}
                public Iterator<Entry<K,V>> iterator(){
                    Iterator<? extends Entry<? extends K,? extends V>> it=entries.iterator();
                    return new Iterator<Entry<K,V>>(){public boolean hasNext(){return it.hasNext();}
                        public Entry<K,V> next(){Entry<? extends K,? extends V> e=it.next();return new AbstractMap.SimpleImmutableEntry<K,V>(e.getKey(),e.getValue());}};
                }
            });
        }
        public V put(K k,V v){throw readOnly();}
        public V remove(Object k){throw readOnly();}
        public void putAll(Map<? extends K,? extends V> m){throw readOnly();}
        public void clear(){throw readOnly();}
        public V putIfAbsent(K k,V v){throw readOnly();}
        public boolean remove(Object k,Object v){throw readOnly();}
        public boolean replace(K k,V a,V b){throw readOnly();}
        public V replace(K k,V v){throw readOnly();}
        public void replaceAll(BiFunction<? super K,? super V,? extends V> f){throw readOnly();}
        public V computeIfAbsent(K k,Function<? super K,? extends V> f){throw readOnly();}
        public V computeIfPresent(K k,BiFunction<? super K,? super V,? extends V> f){throw readOnly();}
        public V compute(K k,BiFunction<? super K,? super V,? extends V> f){throw readOnly();}
        public V merge(K k,V v,BiFunction<? super V,? super V,? extends V> f){throw readOnly();}
    }
}
