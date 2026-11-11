package java.util;
public class HashSet<E> extends AbstractSet<E> implements Cloneable,java.io.Serializable {
    private final HashMap<E,Boolean> map;
    public HashSet(){map=new HashMap<E,Boolean>();}
    public HashSet(int capacity){map=new HashMap<E,Boolean>(capacity);}
    public HashSet(int capacity,float loadFactor){map=new HashMap<E,Boolean>(capacity,loadFactor);}
    public HashSet(Collection<? extends E> source){this();addAll(source);}
    public static <T> HashSet<T> newHashSet(int expected){if(expected<0)throw new IllegalArgumentException();return new HashSet<T>((int)Math.min(1<<30,Math.ceil(expected/.75)));}
    public int size(){return map.size();}
    public boolean contains(Object value){return map.containsKey(value);}
    public boolean add(E value){return map.put(value,Boolean.TRUE)==null;}
    public boolean remove(Object value){return map.remove(value)!=null;}
    public void clear(){map.clear();}
    public Iterator<E> iterator(){return map.keySet().iterator();}
    public Object clone(){return new HashSet<E>(this);}
}
