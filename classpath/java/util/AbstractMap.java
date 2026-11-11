package java.util;
public abstract class AbstractMap<K,V> implements Map<K,V> {
    protected AbstractMap() {}
    public abstract Set<Entry<K,V>> entrySet();
    public int size(){return entrySet().size();}
    public boolean isEmpty(){return size()==0;}
    public boolean containsKey(Object key){for(Entry<K,V> e:entrySet())if(Objects.equals(key,e.getKey()))return true;return false;}
    public boolean containsValue(Object value){for(Entry<K,V> e:entrySet())if(Objects.equals(value,e.getValue()))return true;return false;}
    public V get(Object key){for(Entry<K,V> e:entrySet())if(Objects.equals(key,e.getKey()))return e.getValue();return null;}
    public V put(K key,V value){throw new UnsupportedOperationException();}
    public V remove(Object key){Iterator<Entry<K,V>> it=entrySet().iterator();while(it.hasNext()){Entry<K,V> e=it.next();if(Objects.equals(key,e.getKey())){V old=e.getValue();it.remove();return old;}}return null;}
    public void putAll(Map<? extends K,? extends V> map){for(Entry<? extends K,? extends V> e:map.entrySet())put(e.getKey(),e.getValue());}
    public void clear(){entrySet().clear();}
    public Set<K> keySet(){return new AbstractSet<K>(){
        public int size(){return AbstractMap.this.size();}
        public boolean contains(Object key){return containsKey(key);}
        public void clear(){AbstractMap.this.clear();}
        public Iterator<K> iterator(){Iterator<Entry<K,V>> it=entrySet().iterator();return new Iterator<K>(){public boolean hasNext(){return it.hasNext();}public K next(){return it.next().getKey();}public void remove(){it.remove();}};}
    };}
    public Collection<V> values(){return new AbstractCollection<V>(){
        public int size(){return AbstractMap.this.size();}
        public boolean contains(Object value){return containsValue(value);}
        public void clear(){AbstractMap.this.clear();}
        public Iterator<V> iterator(){Iterator<Entry<K,V>> it=entrySet().iterator();return new Iterator<V>(){public boolean hasNext(){return it.hasNext();}public V next(){return it.next().getValue();}public void remove(){it.remove();}};}
    };}
    public boolean equals(Object other){if(other==this)return true;if(!(other instanceof Map<?,?>))return false;Map<?,?> map=(Map<?,?>)other;if(map.size()!=size())return false;for(Entry<K,V> e:entrySet()){Object value=map.get(e.getKey());if(!Objects.equals(e.getValue(),value)||(value==null&&!map.containsKey(e.getKey())))return false;}return true;}
    public int hashCode(){int h=0;for(Entry<K,V> e:entrySet())h+=e.hashCode();return h;}
    public String toString(){StringBuilder b=new StringBuilder("{");boolean first=true;for(Entry<K,V> e:entrySet()){if(!first)b.append(", ");first=false;b.append(e.getKey()==this?"(this Map)":e.getKey()).append('=').append(e.getValue()==this?"(this Map)":e.getValue());}return b.append('}').toString();}
    public static class SimpleEntry<K,V> implements Entry<K,V>,java.io.Serializable {
        final K key;V value;   // package access: HashMap reads them directly
        public SimpleEntry(K key,V value){this.key=key;this.value=value;}
        public SimpleEntry(Entry<? extends K,? extends V> e){this(e.getKey(),e.getValue());}
        public K getKey(){return key;}public V getValue(){return value;}
        public V setValue(V next){V old=value;value=next;return old;}
        public boolean equals(Object other){if(!(other instanceof Entry<?,?>))return false;Entry<?,?> e=(Entry<?,?>)other;return Objects.equals(key,e.getKey())&&Objects.equals(value,e.getValue());}
        public int hashCode(){return Objects.hashCode(key)^Objects.hashCode(value);}
        public String toString(){return key+"="+value;}
    }
    public static class SimpleImmutableEntry<K,V> implements Entry<K,V>,java.io.Serializable {
        private final K key;private final V value;
        public SimpleImmutableEntry(K key,V value){this.key=key;this.value=value;}
        public SimpleImmutableEntry(Entry<? extends K,? extends V> e){this(e.getKey(),e.getValue());}
        public K getKey(){return key;}public V getValue(){return value;}
        public V setValue(V next){throw new UnsupportedOperationException();}
        public boolean equals(Object other){if(!(other instanceof Entry<?,?>))return false;Entry<?,?> e=(Entry<?,?>)other;return Objects.equals(key,e.getKey())&&Objects.equals(value,e.getValue());}
        public int hashCode(){return Objects.hashCode(key)^Objects.hashCode(value);}
        public String toString(){return key+"="+value;}
    }
}
