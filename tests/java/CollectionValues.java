import java.util.*;
import java.util.function.*;
public class CollectionValues {
    static void check(boolean b){if(!b)throw new AssertionError();}
    public static int list(int seed){
        ArrayList<Integer> a=new ArrayList<>(0);int x=seed,h=0;
        for(int i=0;i<300;i++){x=x*1664525+1013904223;int index=(x&Integer.MAX_VALUE)%(a.size()+1);a.add(index,x);}
        a.addAll(11,a.subList(5,15));
        for(int i=0;i<100;i++){x=x*1664525+1013904223;h=31*h+a.remove((x&Integer.MAX_VALUE)%a.size());}
        a.add(null);check(a.contains(null));a.remove(null);
        ListIterator<Integer> it=a.listIterator();int n=0;while(it.hasNext()){int v=it.next();if((n++&3)==0)it.remove();else it.set(v^seed);}
        it=a.listIterator(a.size());while(it.hasPrevious()){int v=it.previous();if((v&31)==0){it.add(seed);it.previous();}}
        a.trimToSize();a.ensureCapacity(500);check(a.equals(a.clone()));
        Integer[] out=a.toArray(new Integer[a.size()+3]);check(out[a.size()]==null&&out.length==a.size()+3);
        check(a.toArray(new Number[0]).getClass()==Number[].class);
        h=31*h+a.hashCode();a.sort(null);check(a.getFirst()<=a.getLast());
        h=31*h+a.hashCode();return h;
    }
    public static int views(int seed){
        List<Integer> a=new ArrayList<>(List.of(1,2,3,4,5,6));List<Integer> b=a.subList(1,5);List<Integer> c=b.subList(1,3);
        c.add(1,seed);check(b.size()==5&&a.size()==7);c.remove(0);c.clear();check(b.equals(List.of(2,5)));
        List<Integer> reverse=a.reversed();check(reverse.reversed()==a);reverse.addFirst(9);reverse.addLast(8);
        ListIterator<Integer> it=reverse.listIterator(1);it.next();it.set(77);it.add(88);it.previous();it.remove();
        int h=a.hashCode()^reverse.hashCode();a.add(0);
        try{b.size();throw new AssertionError();}catch(ConcurrentModificationException e){h++;}
        return h;
    }
    static final class Key {
        final int value;Key(int v){value=v;}
        public int hashCode(){return value&3;}
        public boolean equals(Object o){return o instanceof Key&&value==((Key)o).value;}
    }
    public static int map(int seed){
        HashMap<Key,Integer> map=new HashMap<>(1,.5f);int x=seed,h=0;
        for(int i=0;i<500;i++){x=x*1664525+1013904223;map.put(new Key((x>>>8)&63),x);}
        for(int i=0;i<64;i++){Integer v=map.get(new Key(i));h=31*h+(v==null?0:v);}
        map.put(null,seed);map.put(new Key(123),null);check(map.containsKey(new Key(123))&&map.containsValue(null));
        check(map.getOrDefault(new Key(123),77)==null);check(map.getOrDefault(new Key(-1),77)==77);
        check(map.putIfAbsent(new Key(123),42)==null);check(map.replace(new Key(123),42,43));
        check(map.remove(new Key(123),43));check(!map.remove(new Key(123),null));
        HashMap<Key,Integer> copy=new HashMap<>(map);check(copy.equals(map)&&copy.hashCode()==map.hashCode());
        Set<Key> keys=map.keySet();Collection<Integer> values=map.values();
        Iterator<Map.Entry<Key,Integer>> it=map.entrySet().iterator();
        while(it.hasNext()){Map.Entry<Key,Integer> e=it.next();if(e.getKey()==null||(e.getKey().value&1)==0)it.remove();else e.setValue(e.getValue()+1);}
        check(keys.size()==map.size()&&values.size()==map.size());
        h=31*h+map.hashCode();keys.remove(new Key(3));values.remove(map.get(new Key(5)));h=31*h+map.size();
        check(map.entrySet().contains(new AbstractMap.SimpleEntry<Key,Integer>(new Key(7),map.get(new Key(7)))));
        keys.clear();check(map.isEmpty()&&values.isEmpty());return h;
    }
    public static int functions(int seed){
        Map<String,Integer> m=new HashMap<>();
        m.computeIfAbsent("a",new Function<String,Integer>(){public Integer apply(String s){return seed;}});
        m.computeIfPresent("a",new BiFunction<String,Integer,Integer>(){public Integer apply(String k,Integer v){return v+1;}});
        m.merge("a",2,new BiFunction<Integer,Integer,Integer>(){public Integer apply(Integer a,Integer b){return a+b;}});
        m.compute("b",new BiFunction<String,Integer,Integer>(){public Integer apply(String k,Integer v){return 7;}});
        m.replaceAll(new BiFunction<String,Integer,Integer>(){public Integer apply(String k,Integer v){return v*2;}});
        int h=m.hashCode();
        ArrayList<Integer> a=new ArrayList<>(List.of(1,2,3,4,5,6));
        a.removeIf(new Predicate<Integer>(){public boolean test(Integer v){return (v&1)==0;}});
        a.replaceAll(new UnaryOperator<Integer>(){public Integer apply(Integer v){return -v;}});
        a.sort(Comparator.reverseOrder());h=31*h+a.hashCode();
        final int[] total={0};a.forEach(new Consumer<Integer>(){public void accept(Integer v){total[0]+=v;}});
        return h+total[0];
    }
    public static int factories(int seed){
        Object immutable=new AbstractMap.SimpleImmutableEntry<>("key",seed);
        check(!(immutable instanceof AbstractMap.SimpleEntry));
        check(immutable.equals(new AbstractMap.SimpleEntry<>("key",seed)));
        List<Integer> list=List.of(1,2,3,4,5,6,7,8,9,10);check(list.equals(List.copyOf(list)));
        Set<Integer> set=Set.of(1,2,3,4,5,6,7,8,9,10);check(set.equals(Set.copyOf(list)));
        Map<String,Integer> map=Map.of("a",1,"b",2,"c",3,"d",4);check(Map.copyOf(map).equals(map));
        check(Map.Entry.copyOf(map.entrySet().iterator().next()).getValue()!=null);
        int n=0;
        try{List.of(1,null);}catch(NullPointerException e){n++;}
        try{Set.of(1,1);}catch(IllegalArgumentException e){n++;}
        try{Map.of("a",1,"a",2);}catch(IllegalArgumentException e){n++;}
        try{list.set(0,seed);}catch(UnsupportedOperationException e){n++;}
        try{set.iterator().remove();}catch(UnsupportedOperationException e){n++;}
        try{map.entrySet().iterator().next().setValue(seed);}catch(UnsupportedOperationException e){n++;}
        check(n==6);return n+list.hashCode()+set.hashCode()+map.hashCode();
    }
    public static int sets(int seed){
        HashSet<Integer> set=new HashSet<>();for(int i=0;i<200;i++)set.add((i*seed)&255);set.add(null);
        HashSet<Integer> copy=new HashSet<>(set);check(copy.equals(set)&&copy.equals(copy.clone()));
        copy.removeAll(new ArrayList<>(List.of(0,1,2,3)));set.retainAll(copy);check(set.equals(copy));
        Iterator<Integer> it=set.iterator();while(it.hasNext()){Integer v=it.next();if(v==null||(v&3)==0)it.remove();}
        return set.size()*31+set.hashCode();
    }
    public static int errors(int seed){
        int n=0;ArrayList<Integer> a=new ArrayList<>(List.of(1,2,3));Iterator<Integer> it=a.iterator();
        try{it.remove();}catch(IllegalStateException e){n++;}
        a.add(seed);try{it.next();}catch(ConcurrentModificationException e){n++;}
        try{a.toArray(new String[0]);}catch(ArrayStoreException e){n++;}
        try{a.subList(3,1);}catch(IllegalArgumentException e){n++;}
        try{a.get(-1);}catch(IndexOutOfBoundsException e){n++;}
        HashMap<Integer,Integer> m=new HashMap<>();m.put(1,1);Iterator<Integer> mi=m.keySet().iterator();m.put(2,2);
        try{mi.next();}catch(ConcurrentModificationException e){n++;}
        try{m.computeIfAbsent(3,new Function<Integer,Integer>(){public Integer apply(Integer key){m.put(4,4);return 3;}});}catch(ConcurrentModificationException e){n++;}
        check(m.containsKey(4)&&!m.containsKey(3));return n;
    }
}
