package java.util;
/** Set over a TreeMap (or a TreeMap view); keys=true marks a map's key-set view, which rejects add. */
@SuppressWarnings("unchecked")
public class TreeSet<E> extends AbstractSet<E> implements NavigableSet<E>,Cloneable,java.io.Serializable {
    private final TreeMap<E,Object> m;private final boolean keys;
    TreeSet(TreeMap<E,?> m,boolean keys){this.m=(TreeMap<E,Object>)m;this.keys=keys;}
    public TreeSet(){this(new TreeMap<E,Object>(),false);}
    public TreeSet(Comparator<? super E> comparator){this(new TreeMap<E,Object>(comparator),false);}
    public TreeSet(Collection<? extends E> c){this();addAll(c);}
    public TreeSet(SortedSet<E> s){this(s.comparator());addAll(s);}
    private NavigableSet<E> wrap(NavigableMap<E,?> view){return new TreeSet<E>((TreeMap<E,?>)view,keys);}
    private static <E> E key(Map.Entry<E,?> e){return e==null?null:e.getKey();}
    public int size(){return m.size();}
    public boolean isEmpty(){return m.isEmpty();}
    public boolean contains(Object o){return m.containsKey(o);}
    public boolean add(E e){if(keys)throw new UnsupportedOperationException();return m.put(e,Boolean.TRUE)==null;}
    public boolean remove(Object o){return m.removeKey(o);}
    public void clear(){m.clear();}
    public Iterator<E> iterator(){return m.new Cursor<E>(true);}
    public Iterator<E> descendingIterator(){return descendingSet().iterator();}
    public NavigableSet<E> descendingSet(){return wrap(m.descendingMap());}
    public Comparator<? super E> comparator(){return m.comparator();}
    public E first(){return m.firstKey();}
    public E last(){return m.lastKey();}
    public E lower(E e){return m.lowerKey(e);}
    public E floor(E e){return m.floorKey(e);}
    public E ceiling(E e){return m.ceilingKey(e);}
    public E higher(E e){return m.higherKey(e);}
    public E pollFirst(){return key(m.pollFirstEntry());}
    public E pollLast(){return key(m.pollLastEntry());}
    public NavigableSet<E> subSet(E from,boolean fromInclusive,E to,boolean toInclusive){return wrap(m.subMap(from,fromInclusive,to,toInclusive));}
    public NavigableSet<E> headSet(E to,boolean inclusive){return wrap(m.headMap(to,inclusive));}
    public NavigableSet<E> tailSet(E from,boolean inclusive){return wrap(m.tailMap(from,inclusive));}
    public SortedSet<E> subSet(E from,E to){return subSet(from,true,to,false);}
    public SortedSet<E> headSet(E to){return headSet(to,false);}
    public SortedSet<E> tailSet(E from){return tailSet(from,true);}
    public Object clone(){return new TreeSet<E>((SortedSet<E>)this);}
}
