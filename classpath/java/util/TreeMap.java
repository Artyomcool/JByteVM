package java.util;
/**
 * Balanced search tree (a treap: BST order on keys, heap order on random priorities, parent links).
 * Nodes never move between keys, so iterators and entries stay valid across rotations.
 * Sub-map and descending views are TreeMaps too: they share the base tree and add bounds and
 * a direction flag, so one set of navigation methods serves the map and all of its views.
 */
@SuppressWarnings("unchecked")
public class TreeMap<K,V> extends AbstractMap<K,V> implements NavigableMap<K,V>,Cloneable,java.io.Serializable {
    static final class Node<K,V> extends AbstractMap.SimpleEntry<K,V> {
        Node<K,V> left,right,parent;final int prio;
        Node(K key,V value,Node<K,V> parent,int prio){super(key,value);this.parent=parent;this.prio=prio;}
    }
    private static final int LT=1,EQ=2,GT=4,HAS_LO=1,LO_IN=2,HAS_HI=4,HI_IN=8,DESC=16;
    private final Comparator<? super K> comparator;
    private final TreeMap<K,V> base;private final Object lo,hi;private final int flags;
    private Node<K,V> root;private int size,modCount,seed=0x2545F491;
    public TreeMap(){this((Comparator<? super K>)null);}
    public TreeMap(Comparator<? super K> comparator){this.comparator=comparator;base=this;lo=hi=null;flags=0;}
    public TreeMap(Map<? extends K,? extends V> m){this((Comparator<? super K>)null);putAll(m);}
    public TreeMap(SortedMap<K,? extends V> m){this(m.comparator());putAll(m);}
    private TreeMap(TreeMap<K,V> b,Object lo,Object hi,int flags){comparator=b.comparator;base=b;this.lo=lo;this.hi=hi;this.flags=flags;}

    private int cmp(Object a,Object b){return comparator==null?((Comparable<Object>)a).compareTo(b):comparator.compare((K)a,(K)b);}
    private boolean tooLow(Object k){if((flags&HAS_LO)==0)return false;int c=cmp(k,lo);return c<0||c==0&&(flags&LO_IN)==0;}
    private boolean tooHigh(Object k){if((flags&HAS_HI)==0)return false;int c=cmp(k,hi);return c>0||c==0&&(flags&HI_IN)==0;}
    private boolean inRange(Object k){return !tooLow(k)&&!tooHigh(k);}

    // ---- base tree operations (always invoked on base) ----
    /** Exact match (EQ) or the nearest node below (LT[|EQ]) / above (GT[|EQ]) key, ignoring view bounds. */
    private Node<K,V> find(Object key,int rel){
        if(rel==EQ&&comparator==null){Comparable<?> k=(Comparable<?>)Objects.requireNonNull(key);}
        Node<K,V> n=root,best=null;
        while(n!=null){
            int c=cmp(key,n.getKey());
            if(c==0&&(rel&EQ)!=0)return n;
            if((rel&LT)!=0?c>0:(rel&GT)!=0&&c<0)best=n;
            n=c>0||c==0&&(rel&GT)!=0?n.right:n.left;
        }
        return best;
    }
    private V insert(K key,V value){
        Node<K,V> p=root,parent=null;int c=0;
        if(p==null)cmp(key,key);else if(comparator==null)Objects.requireNonNull(key);
        while(p!=null){c=cmp(key,p.getKey());if(c==0)return p.setValue(value);parent=p;p=c<0?p.left:p.right;}
        seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;
        Node<K,V> x=new Node<K,V>(key,value,parent,seed);
        if(parent==null)root=x;else if(c<0)parent.left=x;else parent.right=x;
        while(x.parent!=null&&x.parent.prio<x.prio)rotate(x);
        size++;modCount++;return null;
    }
    /** Lifts x above its parent. */
    private void rotate(Node<K,V> x){
        Node<K,V> p=x.parent,g=p.parent;
        if(x==p.left){p.left=x.right;if(x.right!=null)x.right.parent=p;x.right=p;}
        else{p.right=x.left;if(x.left!=null)x.left.parent=p;x.left=p;}
        p.parent=x;x.parent=g;
        if(g==null)root=x;else if(g.left==p)g.left=x;else g.right=x;
    }
    private void delete(Node<K,V> n){
        while(n.left!=null&&n.right!=null)rotate(n.left.prio>n.right.prio?n.left:n.right);
        Node<K,V> c=n.left!=null?n.left:n.right,p=n.parent;
        if(c!=null)c.parent=p;
        if(p==null)root=c;else if(p.left==n)p.left=c;else p.right=c;
        size--;modCount++;
    }

    // ---- view-aware navigation ----
    /** Lowest (high=false) or highest in-range node in key order. */
    private Node<K,V> edge(boolean high){
        Node<K,V> n;
        if((flags&(high?HAS_HI:HAS_LO))!=0)n=base.find(high?hi:lo,high?((flags&HI_IN)!=0?LT|EQ:LT):((flags&LO_IN)!=0?GT|EQ:GT));
        else if((n=base.root)!=null)while((high?n.right:n.left)!=null)n=high?n.right:n.left;
        return n==null||!inRange(n.getKey())?null:n;
    }
    /** First (last=false) or last node in view order. */
    private Node<K,V> end(boolean last){return edge(last!=((flags&DESC)!=0));}
    /** Nearest node relative to key in view order; rel is LT, LT|EQ, GT|EQ or GT. */
    private Node<K,V> nav(Object key,int rel){
        if((flags&DESC)!=0)rel=rel&EQ|(rel&LT)<<2|(rel&GT)>>2;
        boolean down=(rel&LT)!=0;
        if(down?tooHigh(key):tooLow(key))return edge(down);
        Node<K,V> n=base.find(key,rel);
        return n==null||!inRange(n.getKey())?null:n;
    }
    /** Next node in view order, or null past the end of the view. */
    private Node<K,V> succ(Node<K,V> n){
        boolean fwd=(flags&DESC)==0;Node<K,V> c=fwd?n.right:n.left;
        if(c!=null)while((fwd?c.left:c.right)!=null)c=fwd?c.left:c.right;
        else{c=n.parent;while(c!=null&&n==(fwd?c.right:c.left)){n=c;c=c.parent;}}
        return c==null||!inRange(c.getKey())?null:c;
    }
    private Node<K,V> node(Object key){return inRange(key)?base.find(key,EQ):null;}
    private static <K,V> Map.Entry<K,V> export(Node<K,V> n){return n==null?null:new SimpleImmutableEntry<K,V>(n);}
    private static <K> K key(Node<K,?> n){if(n==null)throw new NoSuchElementException();return n.getKey();}
    private static <K> K keyOrNull(Node<K,?> n){return n==null?null:n.getKey();}
    private Map.Entry<K,V> poll(Node<K,V> n){Map.Entry<K,V> e=export(n);if(n!=null)base.delete(n);return e;}

    public Comparator<? super K> comparator(){return (flags&DESC)!=0?Collections.reverseOrder(comparator):comparator;}
    public int size(){if(this==base)return size;int k=0;for(Node<K,V> n=end(false);n!=null;n=succ(n))k++;return k;}
    public boolean isEmpty(){return end(false)==null;}
    public boolean containsKey(Object key){return node(key)!=null;}
    public V get(Object key){Node<K,V> n=node(key);return n==null?null:n.getValue();}
    public V put(K key,V value){if(!inRange(key))throw new IllegalArgumentException("key out of range");return base.insert(key,value);}
    public V remove(Object key){Node<K,V> n=node(key);if(n==null)return null;base.delete(n);return n.getValue();}
    boolean removeKey(Object key){Node<K,V> n=node(key);if(n!=null)base.delete(n);return n!=null;}
    public void clear(){if(this==base){root=null;size=0;modCount++;}else for(Iterator<?> it=new Cursor<Object>(false);it.hasNext();){it.next();it.remove();}}
    public K firstKey(){return key(end(false));}
    public K lastKey(){return key(end(true));}
    public Map.Entry<K,V> firstEntry(){return export(end(false));}
    public Map.Entry<K,V> lastEntry(){return export(end(true));}
    public Map.Entry<K,V> pollFirstEntry(){return poll(end(false));}
    public Map.Entry<K,V> pollLastEntry(){return poll(end(true));}
    public Map.Entry<K,V> lowerEntry(K key){return export(nav(key,LT));}
    public Map.Entry<K,V> floorEntry(K key){return export(nav(key,LT|EQ));}
    public Map.Entry<K,V> ceilingEntry(K key){return export(nav(key,GT|EQ));}
    public Map.Entry<K,V> higherEntry(K key){return export(nav(key,GT));}
    public K lowerKey(K key){return keyOrNull(nav(key,LT));}
    public K floorKey(K key){return keyOrNull(nav(key,LT|EQ));}
    public K ceilingKey(K key){return keyOrNull(nav(key,GT|EQ));}
    public K higherKey(K key){return keyOrNull(nav(key,GT));}

    public NavigableMap<K,V> descendingMap(){return new TreeMap<K,V>(base,lo,hi,flags^DESC);}
    public Set<K> keySet(){return navigableKeySet();}
    public NavigableSet<K> navigableKeySet(){return new TreeSet<K>(this,true);}
    public NavigableSet<K> descendingKeySet(){return descendingMap().navigableKeySet();}
    public NavigableMap<K,V> subMap(K from,boolean fromInclusive,K to,boolean toInclusive){return view(true,from,fromInclusive,true,to,toInclusive);}
    public NavigableMap<K,V> headMap(K to,boolean inclusive){return view(false,null,false,true,to,inclusive);}
    public NavigableMap<K,V> tailMap(K from,boolean inclusive){return view(true,from,inclusive,false,null,false);}
    public SortedMap<K,V> subMap(K from,K to){return subMap(from,true,to,false);}
    public SortedMap<K,V> headMap(K to){return headMap(to,false);}
    public SortedMap<K,V> tailMap(K from){return tailMap(from,true);}
    private boolean inRange(Object k,boolean inclusive){return inclusive?inRange(k):((flags&HAS_LO)==0||cmp(k,lo)>=0)&&((flags&HAS_HI)==0||cmp(hi,k)>=0);}
    /** Narrows this view; from/to are in view order, missing bounds are inherited. */
    private TreeMap<K,V> view(boolean hasFrom,Object from,boolean fi,boolean hasTo,Object to,boolean ti){
        if(hasFrom&&!inRange(from,fi))throw new IllegalArgumentException("fromKey out of range");
        if(hasTo&&!inRange(to,ti))throw new IllegalArgumentException("toKey out of range");
        if((flags&DESC)!=0){boolean b=hasFrom;hasFrom=hasTo;hasTo=b;b=fi;fi=ti;ti=b;Object o=from;from=to;to=o;}
        int f=flags&DESC;Object l=lo,h=hi;
        if(hasFrom){l=from;f|=HAS_LO|(fi?LO_IN:0);}else f|=flags&(HAS_LO|LO_IN);
        if(hasTo){h=to;f|=HAS_HI|(ti?HI_IN:0);}else f|=flags&(HAS_HI|HI_IN);
        if((f&HAS_LO)!=0&&(f&HAS_HI)!=0){if(cmp(l,h)>0)throw new IllegalArgumentException("fromKey > toKey");}
        else{if((f&HAS_LO)!=0)cmp(l,l);if((f&HAS_HI)!=0)cmp(h,h);}
        return new TreeMap<K,V>(base,l,h,f);
    }
    private Node<K,V> entry(Object o){
        if(!(o instanceof Map.Entry<?,?>))return null;
        Map.Entry<?,?> e=(Map.Entry<?,?>)o;Node<K,V> n=node(e.getKey());
        return n!=null&&Objects.equals(n.getValue(),e.getValue())?n:null;
    }
    public Set<Map.Entry<K,V>> entrySet(){return new AbstractSet<Map.Entry<K,V>>(){
        public int size(){return TreeMap.this.size();}
        public Iterator<Map.Entry<K,V>> iterator(){return new Cursor<Map.Entry<K,V>>(false);}
        public boolean contains(Object o){return entry(o)!=null;}
        public boolean remove(Object o){Node<K,V> n=entry(o);if(n!=null)base.delete(n);return n!=null;}
        public void clear(){TreeMap.this.clear();}
    };}
    /** Iterates nodes (keys=false) or keys in view order. */
    final class Cursor<T> implements Iterator<T> {
        final boolean keys;Node<K,V> next=end(false),last;int expected=base.modCount;
        Cursor(boolean keys){this.keys=keys;}
        public boolean hasNext(){return next!=null;}
        public T next(){
            Node<K,V> n=next;
            if(n==null)throw new NoSuchElementException();
            if(expected!=base.modCount)throw new ConcurrentModificationException();
            next=succ(n);last=n;return (T)(keys?n.getKey():n);
        }
        public void remove(){
            if(last==null)throw new IllegalStateException();
            if(expected!=base.modCount)throw new ConcurrentModificationException();
            base.delete(last);last=null;expected=base.modCount;
        }
    }
    public Object clone(){return new TreeMap<K,V>((SortedMap<K,V>)this);}
}
