package java.util;
import java.util.function.*;
public interface Map<K,V> {
    int size(); boolean isEmpty(); boolean containsKey(Object key); boolean containsValue(Object value);
    V get(Object key); V put(K key,V value); V remove(Object key); void putAll(Map<? extends K,? extends V> map); void clear();
    Set<K> keySet(); Collection<V> values(); Set<Entry<K,V>> entrySet();
    interface Entry<K,V> {
        K getKey(); V getValue(); V setValue(V value);
        static <K,V> Entry<K,V> copyOf(Entry<? extends K,? extends V> e){return Map.entry(e.getKey(),e.getValue());}
        static <K extends Comparable<? super K>,V> Comparator<Entry<K,V>> comparingByKey(){return new Comparator<Entry<K,V>>(){public int compare(Entry<K,V> a,Entry<K,V> b){return a.getKey().compareTo(b.getKey());}};}
        static <K,V extends Comparable<? super V>> Comparator<Entry<K,V>> comparingByValue(){return new Comparator<Entry<K,V>>(){public int compare(Entry<K,V> a,Entry<K,V> b){return a.getValue().compareTo(b.getValue());}};}
    }
    default V getOrDefault(Object key,V fallback){V v=get(key);return v!=null||containsKey(key)?v:fallback;}
    default V putIfAbsent(K key,V value){V old=get(key);return old==null?put(key,value):old;}
    default boolean remove(Object key,Object value){V old=get(key);if(!Objects.equals(old,value)||(old==null&&!containsKey(key)))return false;remove(key);return true;}
    default boolean replace(K key,V oldValue,V newValue){V old=get(key);if(!Objects.equals(old,oldValue)||(old==null&&!containsKey(key)))return false;put(key,newValue);return true;}
    default V replace(K key,V value){return containsKey(key)?put(key,value):null;}
    default void forEach(BiConsumer<? super K,? super V> action){Objects.requireNonNull(action);for(Entry<K,V> e:entrySet())action.accept(e.getKey(),e.getValue());}
    default void replaceAll(BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);for(Entry<K,V> e:entrySet())e.setValue(action.apply(e.getKey(),e.getValue()));}
    default V computeIfAbsent(K key,Function<? super K,? extends V> action){Objects.requireNonNull(action);V old=get(key);if(old==null){V next=action.apply(key);if(next!=null){put(key,next);return next;}}return old;}
    default V computeIfPresent(K key,BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);V old=get(key);if(old==null)return null;V next=action.apply(key,old);if(next==null)remove(key);else put(key,next);return next;}
    default V compute(K key,BiFunction<? super K,? super V,? extends V> action){Objects.requireNonNull(action);V next=action.apply(key,get(key));if(next==null)remove(key);else put(key,next);return next;}
    default V merge(K key,V value,BiFunction<? super V,? super V,? extends V> action){Objects.requireNonNull(value);Objects.requireNonNull(action);V old=get(key);V next=old==null?value:action.apply(old,value);if(next==null)remove(key);else put(key,next);return next;}
    static <K,V> Entry<K,V> entry(K key,V value){return new AbstractMap.SimpleImmutableEntry<K,V>(Objects.requireNonNull(key),Objects.requireNonNull(value));}
    static <K,V> Map<K,V> ofEntries(Entry<? extends K,? extends V>... entries){HashMap<K,V> map=new HashMap<K,V>();for(Entry<? extends K,? extends V> e:entries){K k=Objects.requireNonNull(e.getKey());V v=Objects.requireNonNull(e.getValue());if(map.containsKey(k))throw new IllegalArgumentException();map.put(k,v);}return new jbv.runtime.Collections.FrozenMap<K,V>(map);}
    static <K,V> Map<K,V> copyOf(Map<? extends K,? extends V> source){HashMap<K,V> map=new HashMap<K,V>();for(Entry<? extends K,? extends V> e:source.entrySet())map.put(Objects.requireNonNull(e.getKey()),Objects.requireNonNull(e.getValue()));return new jbv.runtime.Collections.FrozenMap<K,V>(map);}
    // BEGIN GENERATED FACTORIES
    static <K,V> Map<K,V> of(){return ofEntries();}
    static <K,V> Map<K,V> of(K k0,V v0){return ofEntries(entry(k0,v0));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1){return ofEntries(entry(k0,v0),entry(k1,v1));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2,K k3,V v3){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2),entry(k3,v3));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2,K k3,V v3,K k4,V v4){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2),entry(k3,v3),entry(k4,v4));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2,K k3,V v3,K k4,V v4,K k5,V v5){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2),entry(k3,v3),entry(k4,v4),entry(k5,v5));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2,K k3,V v3,K k4,V v4,K k5,V v5,K k6,V v6){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2),entry(k3,v3),entry(k4,v4),entry(k5,v5),entry(k6,v6));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2,K k3,V v3,K k4,V v4,K k5,V v5,K k6,V v6,K k7,V v7){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2),entry(k3,v3),entry(k4,v4),entry(k5,v5),entry(k6,v6),entry(k7,v7));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2,K k3,V v3,K k4,V v4,K k5,V v5,K k6,V v6,K k7,V v7,K k8,V v8){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2),entry(k3,v3),entry(k4,v4),entry(k5,v5),entry(k6,v6),entry(k7,v7),entry(k8,v8));}
    static <K,V> Map<K,V> of(K k0,V v0,K k1,V v1,K k2,V v2,K k3,V v3,K k4,V v4,K k5,V v5,K k6,V v6,K k7,V v7,K k8,V v8,K k9,V v9){return ofEntries(entry(k0,v0),entry(k1,v1),entry(k2,v2),entry(k3,v3),entry(k4,v4),entry(k5,v5),entry(k6,v6),entry(k7,v7),entry(k8,v8),entry(k9,v9));}
    // END GENERATED FACTORIES
}
