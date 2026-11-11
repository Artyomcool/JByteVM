package java.util;
/** HashMap whose nodes also form a doubly linked list in insertion or access order. */
public class LinkedHashMap<K,V> extends HashMap<K,V> {
    private static final class Linked<K,V> extends HashMap.Node<K,V> {
        Linked<K,V> before,after;
        Linked(int hash,K key,V value,HashMap.Node<K,V> next){super(hash,key,value,next);}
    }
    private final boolean accessOrder;private boolean copying;private Linked<K,V> head,tail;
    public LinkedHashMap(){this(16,.75f,false);}
    public LinkedHashMap(int capacity){this(capacity,.75f,false);}
    public LinkedHashMap(int capacity,float loadFactor){this(capacity,loadFactor,false);}
    public LinkedHashMap(int capacity,float loadFactor,boolean accessOrder){super(capacity,loadFactor);this.accessOrder=accessOrder;}
    public LinkedHashMap(Map<? extends K,? extends V> m){this();copying=true;putAll(m);copying=false;}
    public static <K,V> LinkedHashMap<K,V> newLinkedHashMap(int expected){if(expected<0)throw new IllegalArgumentException();return new LinkedHashMap<K,V>((int)Math.min(1<<30,Math.ceil(expected/.75)));}
    protected boolean removeEldestEntry(Map.Entry<K,V> eldest){return false;}
    private void append(Linked<K,V> x){x.before=tail;x.after=null;if(tail==null)head=x;else tail.after=x;tail=x;}
    HashMap.Node<K,V> newNode(int hash,K key,V value,HashMap.Node<K,V> next){Linked<K,V> x=new Linked<K,V>(hash,key,value,next);append(x);return x;}
    void removed(HashMap.Node<K,V> n){Linked<K,V> x=(Linked<K,V>)n;if(x.before==null)head=x.after;else x.before.after=x.after;if(x.after==null)tail=x.before;else x.after.before=x.before;}
    void accessed(HashMap.Node<K,V> n){if(accessOrder&&tail!=n){removed(n);append((Linked<K,V>)n);modCount++;}}
    void inserted(){Linked<K,V> first=head;if(!copying&&first!=null&&removeEldestEntry(first))remove(first.getKey());}
    HashMap.Node<K,V> after(HashMap.Node<K,V> n){return n==null?head:((Linked<K,V>)n).after;}
    public void clear(){super.clear();head=tail=null;}
    public Object clone(){LinkedHashMap<K,V> m=new LinkedHashMap<K,V>(16,.75f,accessOrder);m.putAll(this);return m;}
}
