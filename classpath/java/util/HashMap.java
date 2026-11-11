package java.util;
import java.util.function.*;
public class HashMap<K,V> extends AbstractMap<K,V> implements Cloneable,java.io.Serializable {
    private Node<K,V>[] table;private int length,modCount,threshold;private final float loadFactor;
    private static final class Node<K,V> extends SimpleEntry<K,V> {
        final int hash;Node<K,V> next;
        Node(int hash,K key,V value,Node<K,V> next){super(key,value);this.hash=hash;this.next=next;}
    }
    public HashMap(){this(16,.75f);}
    public HashMap(int capacity){this(capacity,.75f);}
    @SuppressWarnings("unchecked") public HashMap(int capacity,float loadFactor){if(capacity<0||!(loadFactor>0))throw new IllegalArgumentException();this.loadFactor=loadFactor;int n=1;while(n<capacity&&n<(1<<30))n<<=1;table=(Node<K,V>[])new Node<?,?>[n];threshold=threshold(n);}
    public HashMap(Map<? extends K,? extends V> other){this();putAll(other);}
    public static <K,V> HashMap<K,V> newHashMap(int expected){if(expected<0)throw new IllegalArgumentException();return new HashMap<K,V>((int)Math.min(1<<30,Math.ceil(expected/.75)));}
    private int threshold(int n){return Math.max(1,(int)(n*loadFactor));}
    private static int hash(Object key){int h=Objects.hashCode(key);return h^(h>>>16);}
    private Node<K,V> node(Object key){int h=hash(key);for(Node<K,V> n=table[h&(table.length-1)];n!=null;n=n.next)if(n.hash==h&&Objects.equals(key,n.getKey()))return n;return null;}
    public int size(){return length;}
    public boolean containsKey(Object key){return node(key)!=null;}
    public V get(Object key){Node<K,V> n=node(key);return n==null?null:n.getValue();}
    public V put(K key,V value){int h=hash(key),i=h&(table.length-1);for(Node<K,V> n=table[i];n!=null;n=n.next)if(n.hash==h&&Objects.equals(key,n.getKey()))return n.setValue(value);table[i]=new Node<K,V>(h,key,value,table[i]);length++;modCount++;if(length>threshold)grow();return null;}
    @SuppressWarnings("unchecked") private void grow(){if(table.length>=1<<30){threshold=Integer.MAX_VALUE;return;}Node<K,V>[] next=(Node<K,V>[])new Node<?,?>[table.length<<1];for(Node<K,V> head:table)while(head!=null){Node<K,V> n=head;head=head.next;int i=n.hash&(next.length-1);n.next=next[i];next[i]=n;}table=next;threshold=threshold(next.length);}
    public V remove(Object key){int h=hash(key),i=h&(table.length-1);Node<K,V> prev=null;for(Node<K,V> n=table[i];n!=null;n=n.next){if(n.hash==h&&Objects.equals(key,n.getKey())){if(prev==null)table[i]=n.next;else prev.next=n.next;length--;modCount++;return n.getValue();}prev=n;}return null;}
    public void clear(){if(length!=0){for(int i=0;i<table.length;i++)table[i]=null;length=0;}modCount++;}
    public Set<Entry<K,V>> entrySet(){return new AbstractSet<Entry<K,V>>(){
        public int size(){return length;}
        public void clear(){HashMap.this.clear();}
        public boolean contains(Object value){if(!(value instanceof Entry<?,?>))return false;Entry<?,?> e=(Entry<?,?>)value;Node<K,V> n=node(e.getKey());return n!=null&&Objects.equals(n.getValue(),e.getValue());}
        public boolean remove(Object value){if(!contains(value))return false;HashMap.this.remove(((Entry<?,?>)value).getKey());return true;}
        public Iterator<Entry<K,V>> iterator(){return new Cursor();}
    };}
    private final class Cursor implements Iterator<Entry<K,V>> {
        int bucket,expected=modCount;Node<K,V> next,last;
        Cursor(){advance();}
        void advance(){while(next==null&&bucket<table.length)next=table[bucket++];}
        void check(){if(expected!=modCount)throw new ConcurrentModificationException();}
        public boolean hasNext(){return next!=null;}
        public Entry<K,V> next(){check();if(next==null)throw new NoSuchElementException();last=next;next=next.next;advance();return last;}
        public void remove(){if(last==null)throw new IllegalStateException();check();HashMap.this.remove(last.getKey());last=null;expected=modCount;}
    }
    private void unchanged(int expected){if(expected!=modCount)throw new ConcurrentModificationException();}
    public V computeIfAbsent(K key,Function<? super K,? extends V> action){Objects.requireNonNull(action);V old=get(key);if(old!=null)return old;int expected=modCount;V next=action.apply(key);unchanged(expected);if(next!=null)put(key,next);return next;}
    public V computeIfPresent(K key,BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);V old=get(key);if(old==null)return null;int expected=modCount;V next=action.apply(key,old);unchanged(expected);if(next==null)remove(key);else put(key,next);return next;}
    public V compute(K key,BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);int expected=modCount;V next=action.apply(key,get(key));unchanged(expected);if(next==null)remove(key);else put(key,next);return next;}
    public V merge(K key,V value,BiFunction<? super V,? super V,? extends V> action){Objects.requireNonNull(value);Objects.requireNonNull(action);int expected=modCount;V old=get(key);V next=old==null?value:action.apply(old,value);unchanged(expected);if(next==null)remove(key);else put(key,next);return next;}
    public void forEach(BiConsumer<? super K,? super V> action){Objects.requireNonNull(action);int expected=modCount;for(Entry<K,V> e:entrySet())action.accept(e.getKey(),e.getValue());unchanged(expected);}
    public void replaceAll(BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);int expected=modCount;for(Entry<K,V> e:entrySet())e.setValue(action.apply(e.getKey(),e.getValue()));unchanged(expected);}
    public Object clone(){return new HashMap<K,V>(this);}
}
