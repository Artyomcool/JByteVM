package java.util;
import java.util.function.*;
public class HashMap<K,V> extends AbstractMap<K,V> implements Cloneable,java.io.Serializable {
    private Node<K,V>[] table;private int length,threshold;int modCount;private final float loadFactor;
    static class Node<K,V> extends SimpleEntry<K,V> {
        final int hash;Node<K,V> next;
        Node(int hash,K key,V value,Node<K,V> next){super(key,value);this.hash=hash;this.next=next;}
    }
    // LinkedHashMap hooks: node creation, value access, removal, insertion (eviction) and iteration order.
    Node<K,V> newNode(int hash,K key,V value,Node<K,V> next){return new Node<K,V>(hash,key,value,next);}
    void accessed(Node<K,V> n){}
    void removed(Node<K,V> n){}
    void inserted(){}
    /** Iteration successor of n (first node for null): rest of its chain, then the next non-empty bucket. */
    Node<K,V> after(Node<K,V> n){if(n!=null&&n.next!=null)return n.next;for(int i=n==null?0:(n.hash&(table.length-1))+1;i<table.length;i++)if(table[i]!=null)return table[i];return null;}
    public HashMap(){this(16,.75f);}
    public HashMap(int capacity){this(capacity,.75f);}
    @SuppressWarnings("unchecked") public HashMap(int capacity,float loadFactor){if(capacity<0||!(loadFactor>0))throw new IllegalArgumentException();this.loadFactor=loadFactor;int n=1;while(n<capacity&&n<(1<<30))n<<=1;table=(Node<K,V>[])new Node<?,?>[n];threshold=threshold(n);}
    public HashMap(Map<? extends K,? extends V> other){this();putAll(other);}
    public static <K,V> HashMap<K,V> newHashMap(int expected){if(expected<0)throw new IllegalArgumentException();return new HashMap<K,V>((int)Math.min(1<<30,Math.ceil(expected/.75)));}
    private int threshold(int n){return Math.max(1,(int)(n*loadFactor));}
    private static int hash(Object key){int h=key==null?0:key.hashCode();return h^(h>>>16);}
    Node<K,V> node(Object key){int h=hash(key);for(Node<K,V> n=table[h&(table.length-1)];n!=null;n=n.next){Object k=n.key;if(n.hash==h&&(k==key||key!=null&&key.equals(k)))return n;}return null;}
    public int size(){return length;}
    public boolean containsKey(Object key){return node(key)!=null;}
    public V get(Object key){Node<K,V> n=node(key);if(n==null)return null;accessed(n);return n.value;}
    public V put(K key,V value){int h=hash(key),i=h&(table.length-1);Node<K,V> last=null;for(Node<K,V> n=table[i];n!=null;n=n.next){Object k=n.key;if(n.hash==h&&(k==key||key!=null&&key.equals(k))){V old=n.value;n.value=value;accessed(n);return old;}last=n;}Node<K,V> node=newNode(h,key,value,null);if(last==null)table[i]=node;else last.next=node;length++;modCount++;if(length>threshold)grow();inserted();return null;}
    @SuppressWarnings("unchecked") private void grow(){if(table.length>=1<<30){threshold=Integer.MAX_VALUE;return;}Node<K,V>[] next=(Node<K,V>[])new Node<?,?>[table.length<<1];int old=table.length;for(int j=0;j<old;j++){Node<K,V> lo=null,hi=null;for(Node<K,V> n=table[j],after;n!=null;n=after){after=n.next;n.next=null;if((n.hash&old)==0){if(lo==null)next[j]=n;else lo.next=n;lo=n;}else{if(hi==null)next[j+old]=n;else hi.next=n;hi=n;}}}table=next;threshold=threshold(next.length);}
    public V remove(Object key){int h=hash(key),i=h&(table.length-1);Node<K,V> prev=null;for(Node<K,V> n=table[i];n!=null;n=n.next){if(n.hash==h&&Objects.equals(key,n.getKey())){if(prev==null)table[i]=n.next;else prev.next=n.next;length--;modCount++;removed(n);return n.getValue();}prev=n;}return null;}
    public void clear(){if(length!=0){for(int i=0;i<table.length;i++)table[i]=null;length=0;}modCount++;}
    public Set<Entry<K,V>> entrySet(){return new AbstractSet<Entry<K,V>>(){
        public int size(){return length;}
        public void clear(){HashMap.this.clear();}
        public boolean contains(Object value){if(!(value instanceof Entry<?,?>))return false;Entry<?,?> e=(Entry<?,?>)value;Node<K,V> n=node(e.getKey());return n!=null&&Objects.equals(n.getValue(),e.getValue());}
        public boolean remove(Object value){if(!contains(value))return false;HashMap.this.remove(((Entry<?,?>)value).getKey());return true;}
        public Iterator<Entry<K,V>> iterator(){return new Cursor();}
    };}
    private final class Cursor implements Iterator<Entry<K,V>> {
        int expected=modCount;Node<K,V> next=after(null),last;
        void check(){if(expected!=modCount)throw new ConcurrentModificationException();}
        public boolean hasNext(){return next!=null;}
        public Entry<K,V> next(){check();if(next==null)throw new NoSuchElementException();last=next;next=after(next);return last;}
        public void remove(){if(last==null)throw new IllegalStateException();check();HashMap.this.remove(last.getKey());last=null;expected=modCount;}
    }
    private void unchanged(int expected){if(expected!=modCount)throw new ConcurrentModificationException();}
    public V computeIfAbsent(K key,Function<? super K,? extends V> action){Objects.requireNonNull(action);Node<K,V> n=node(key);V old=n==null?null:n.getValue();if(old!=null){accessed(n);return old;}int expected=modCount;V next=action.apply(key);unchanged(expected);if(next!=null)put(key,next);return next;}
    public V computeIfPresent(K key,BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);Node<K,V> n=node(key);V old=n==null?null:n.getValue();if(old==null)return null;int expected=modCount;V next=action.apply(key,old);unchanged(expected);if(next==null)remove(key);else put(key,next);return next;}
    public V compute(K key,BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);V old=get(key);int expected=modCount;V next=action.apply(key,old);unchanged(expected);if(next==null)remove(key);else put(key,next);return next;}
    public V merge(K key,V value,BiFunction<? super V,? super V,? extends V> action){Objects.requireNonNull(value);Objects.requireNonNull(action);V old=get(key);int expected=modCount;V next=old==null?value:action.apply(old,value);unchanged(expected);if(next==null)remove(key);else put(key,next);return next;}
    public void forEach(BiConsumer<? super K,? super V> action){Objects.requireNonNull(action);int expected=modCount;for(Entry<K,V> e:entrySet())action.accept(e.getKey(),e.getValue());unchanged(expected);}
    public void replaceAll(BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);int expected=modCount;for(Entry<K,V> e:entrySet())e.setValue(action.apply(e.getKey(),e.getValue()));unchanged(expected);}
    public boolean replace(K key,V oldValue,V newValue){Node<K,V> n=node(key);if(n==null||!Objects.equals(n.getValue(),oldValue))return false;n.setValue(newValue);accessed(n);return true;}
    public boolean remove(Object key,Object value){Node<K,V> n=node(key);if(n==null||!Objects.equals(n.getValue(),value))return false;remove(key);return true;}
    public Object clone(){return new HashMap<K,V>(this);}
}
