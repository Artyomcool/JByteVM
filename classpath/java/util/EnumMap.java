package java.util;
/** Values indexed by ordinal; NULL marks a present null value. Iterators are not fail-fast (as in the JDK). */
@SuppressWarnings("unchecked")
public class EnumMap<K extends Enum<K>,V> extends AbstractMap<K,V> implements Cloneable,java.io.Serializable {
    private static final Object NULL=new Object();
    private final Class<K> type;private final Object[] keys;private final Object[] vals;private int size;
    public EnumMap(Class<K> type){this.type=type;keys=type.getEnumConstants();vals=new Object[keys.length];}
    public EnumMap(EnumMap<K,? extends V> m){this((Map<K,? extends V>)m);}
    public EnumMap(Map<K,? extends V> m){this(m instanceof EnumMap<?,?>?((EnumMap<K,?>)m).type:first(m));putAll(m);}
    private static <K extends Enum<K>> Class<K> first(Map<K,?> m){if(m.isEmpty())throw new IllegalArgumentException("Specified map is empty");return m.keySet().iterator().next().getDeclaringClass();}
    private int index(Object k){if(k==null)return -1;Class<?> c=k.getClass();return c==type||c.getSuperclass()==type?((Enum<?>)k).ordinal():-1;}
    private static <V> V unmask(Object v){return v==NULL?null:(V)v;}
    public int size(){return size;}
    public boolean containsKey(Object k){int i=index(k);return i>=0&&vals[i]!=null;}
    public boolean containsValue(Object v){v=v==null?NULL:v;for(Object x:vals)if(v.equals(x))return true;return false;}
    public V get(Object k){int i=index(k);return i<0?null:unmask(vals[i]);}
    public V put(K k,V v){
        int i=index(Objects.requireNonNull(k));if(i<0)throw new ClassCastException(k.getClass()+" != "+type);
        Object old=vals[i];vals[i]=v==null?NULL:v;if(old==null)size++;return unmask(old);
    }
    public V remove(Object k){int i=index(k);if(i<0)return null;Object old=vals[i];vals[i]=null;if(old!=null)size--;return unmask(old);}
    public void clear(){Arrays.fill(vals,null);size=0;}
    public Set<Map.Entry<K,V>> entrySet(){return new AbstractSet<Map.Entry<K,V>>(){
        public int size(){return size;}
        public Iterator<Map.Entry<K,V>> iterator(){return new Iterator<Map.Entry<K,V>>(){
            int index,last=-1;
            public boolean hasNext(){while(index<vals.length&&vals[index]==null)index++;return index!=vals.length;}
            public Map.Entry<K,V> next(){
                if(!hasNext())throw new NoSuchElementException();last=index++;
                return new SimpleEntry<K,V>((K)keys[last],unmask(vals[last])){public V setValue(V v){super.setValue(v);return put(getKey(),v);}};
            }
            public void remove(){if(last<0)throw new IllegalStateException();if(vals[last]!=null){vals[last]=null;size--;}last=-1;}
        };}
    };}
    public EnumMap<K,V> clone(){return new EnumMap<K,V>(this);}
}
