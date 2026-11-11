import java.util.*;
import java.util.function.*;
/**
 * Deques, heaps, linked and sorted maps/sets, enum sets/maps hashed for HotSpot comparison.
 * Avoids HashMap/HashSet iteration order and identity hash codes (enums), which legitimately differ.
 */
public class CollectionValues2 {
    static int h;
    static void mix(int v){h=h*31+v;}
    static void mix(String s){mix(s==null?-7:s.hashCode());}
    static void mix(boolean b){mix(b?1:0);}
    static void mix(Object o){mix(String.valueOf(o));}
    static void fail(Runnable r){try{r.run();mix(0);}catch(RuntimeException e){mix(e.getClass().getName());}}
    static Integer v(Random r,int n){return r.nextInt(n);}
    /** Iterates, removing pseudo-randomly; mixes the visited sequence. */
    static void walk(Iterator<?> it,Random r){while(it.hasNext()){mix(it.next());if(r.nextInt(3)==0)it.remove();}fail(it::next);}

    enum Color{RED,GREEN{public String toString(){return "green";}},BLUE,CYAN,MAGENTA,YELLOW,BLACK}
    enum Wide{W0,W1,W2,W3,W4,W5,W6,W7,W8,W9,W10,W11,W12,W13,W14,W15,W16,W17,W18,W19,W20,W21,W22,W23,W24,W25,W26,W27,W28,W29,W30,W31,W32,W33,W34,W35,W36,W37,W38,W39,
        W40,W41,W42,W43,W44,W45,W46,W47,W48,W49,W50,W51,W52,W53,W54,W55,W56,W57,W58,W59,W60,W61,W62,W63,W64,W65,W66,W67,W68,W69{int x(){return 1;}},W70,W71,W72,W73,W74,W75,W76,W77,W78,W79}

    public static int deques(int seed){
        h=seed;Random r=new Random(seed);
        for(int round=0;round<2;round++){
            Deque<Integer> base=round==0?new ArrayDeque<>(2):new LinkedList<>();Deque<Integer> d=base;
            for(int i=0;i<300;i++){
                if(i%60==59){d=d==base?base.reversed():base;mix(d.toString());}
                Integer x=v(r,20);
                switch(r.nextInt(16)){
                    case 0,1->d.addFirst(x);
                    case 2,3->mix(d.offerLast(x));
                    case 4->d.push(x);
                    case 5->mix(d.pollFirst());
                    case 6->mix(d.pollLast());
                    case 7->mix(d.peekFirst()+"/"+d.peekLast()+"/"+d.peek());
                    case 8->{Deque<Integer> dd=d;fail(()->mix(dd.removeFirst()));fail(()->mix(dd.getLast()));fail(()->mix(dd.element()));}
                    case 9->mix(d.removeFirstOccurrence(x)+" "+d.removeLastOccurrence(x+1)+" "+d.remove(x+2));
                    case 10->mix(d.contains(x));
                    case 11->walk(d.iterator(),r);
                    case 12->walk(d.descendingIterator(),r);
                    case 13->{int k=r.nextInt(5);mix(d.removeIf(y->y!=null&&y%5==k));}
                    case 14->{mix(d.addAll(List.of(x,x+1)));mix(Arrays.toString(d.toArray()));}
                    default->{Deque<Integer> dd=d;fail(()->dd.addFirst(null));fail(()->mix(dd.offer(null)));mix(d.size());}
                }
            }
            mix(base.toString());mix(base.size());
            while(!base.isEmpty())mix(r.nextBoolean()?base.pop():base.removeLast());
            fail(base::pop);fail(base::remove);mix(base.poll());
        }
        ArrayDeque<String> a=new ArrayDeque<>(List.of("a","b","c"));ArrayDeque<String> c=a.clone();c.addFirst("z");mix(a+" "+c);
        Deque<String> rv=a.reversed();rv.addFirst("first");rv.addLast("last");mix(a+" "+rv+" "+rv.peekFirst()+" "+rv.pollLast());
        return h;
    }

    public static int lists(int seed){
        h=seed;Random r=new Random(seed);
        LinkedList<Integer> l=new LinkedList<>();
        for(int i=0;i<200;i++){
            int n=l.size(),i1=r.nextInt(n+2)-1,i2=r.nextInt(n+2)-1;Integer x=r.nextInt(9)==0?null:v(r,30);
            switch(r.nextInt(14)){
                case 0,1->l.add(x);
                case 2->fail(()->l.add(i1,x));
                case 3->fail(()->mix(l.get(i1)));
                case 4->fail(()->mix(l.set(i1,x)));
                case 5->fail(()->mix(l.remove(i1)));
                case 6->mix(l.indexOf(x)+" "+l.lastIndexOf(x)+" "+l.contains(x));
                case 7->fail(()->mix(l.subList(i1,i2)));
                case 8->{if(i1>=0&&i2>=i1&&i2<=n){List<Integer> s=l.subList(i1,i2);s.add(7);mix(s+" "+l);if(r.nextBoolean())s.clear();}}
                case 9->{ListIterator<Integer> it=l.listIterator(Math.max(0,Math.min(n,i1)));
                    for(int k=0;k<8;k++){int op=r.nextInt(6);
                        if(op==0)fail(()->mix(it.next()));else if(op==1)fail(()->mix(it.previous()));else if(op==2)fail(it::remove);
                        else if(op==3)fail(()->it.set(5));else if(op==4)it.add(6);else mix(it.nextIndex()*10+it.previousIndex());}}
                case 10->{l.sort(Comparator.nullsLast(Comparator.<Integer>naturalOrder()));mix(l);}
                case 11->{LinkedList<Integer> rl=l.reversed();rl.addFirst(-1);rl.add(1,-2);mix(rl+" "+rl.getFirst()+" "+l.getLast()+" "+rl.indexOf(-2));walk(rl.iterator(),r);}
                case 12->{l.replaceAll(y->y==null?0:y+1);mix(l.hashCode());}
                default->{fail(()->{Iterator<Integer> it=l.iterator();l.add(1);it.next();});mix(l.equals(new ArrayList<>(l)));}
            }
        }
        mix(l.toString());mix(l.hashCode());mix(((LinkedList<?>)l.clone()).size());
        LinkedList<String> e=new LinkedList<>();fail(e::getFirst);fail(e::removeLast);fail(e::element);mix(e.peekLast());mix(e.pollFirst());
        return h;
    }

    public static int heaps(int seed){
        h=seed;Random r=new Random(seed);
        List<Comparator<Integer>> orders=List.of(Comparator.naturalOrder(),Comparator.reverseOrder(),(a,b)->a%7-b%7,Comparator.comparingInt(a->a/4));
        for(int round=0;round<5;round++){
            PriorityQueue<Integer> q=round==4?new PriorityQueue<>():new PriorityQueue<>(1+r.nextInt(4),orders.get(round));
            for(int i=0;i<250;i++){
                Integer x=v(r,round<2?100:20);
                switch(r.nextInt(10)){
                    case 0,1,2,3->q.offer(x);
                    case 4->mix(q.poll());
                    case 5->mix(q.remove(x));
                    case 6->walk(q.iterator(),r);
                    case 7->{int k=r.nextInt(4);mix(q.removeIf(y->y%4==k));}
                    case 8->mix(q.peek()+" "+q.contains(x)+" "+q.size());
                    default->mix(q.toString());
                }
            }
            mix(q.toString());mix(Arrays.toString(q.toArray()));
            mix(new PriorityQueue<>(q).toString());mix(new PriorityQueue<>(new ArrayList<>(q)).toString());
            mix(q.retainAll(List.of(1,2,3,4,5,6,7,8)));mix(q.toString());
            StringBuilder b=new StringBuilder();while(!q.isEmpty())b.append(q.remove()).append(',');mix(b.toString());
            fail(q::remove);fail(q::element);fail(()->q.add(null));
        }
        TreeSet<Integer> sorted=new TreeSet<>(Comparator.reverseOrder());for(int i=0;i<30;i++)sorted.add(r.nextInt(50));
        PriorityQueue<Integer> fromSorted=new PriorityQueue<>(sorted);fromSorted.add(25);mix(fromSorted.toString());mix(fromSorted.comparator()!=null);
        fail(()->new PriorityQueue<Object>().add(new Object()));fail(()->new PriorityQueue<Integer>(0));
        return h;
    }

    public static int linkedMaps(int seed){
        h=seed;Random r=new Random(seed);
        for(int round=0;round<3;round++){
            int max=round==2?6:Integer.MAX_VALUE;boolean access=round>0;
            Map<Integer,String> m=new LinkedHashMap<>(4,.75f,access){protected boolean removeEldestEntry(Map.Entry<Integer,String> e){return size()>max;}};
            for(int i=0;i<300;i++){
                Integer k=v(r,15);String val=r.nextInt(8)==0?null:"v"+r.nextInt(4);
                switch(r.nextInt(14)){
                    case 0,1,2->mix(m.put(k,val));
                    case 3->mix(m.get(k));
                    case 4->mix(m.getOrDefault(k,"dflt"));
                    case 5->mix(m.remove(k));
                    case 6->mix(m.putIfAbsent(k,val));
                    case 7->mix(m.computeIfAbsent(k,x->"c"+x));
                    case 8->mix(m.computeIfPresent(k,(x,y)->y==null||y.length()>3?null:y+"p"));
                    case 9->mix(m.merge(k,"m",(x,y)->x.length()>4?null:x+y));
                    case 10->walk(m.entrySet().iterator(),r);
                    case 11->mix(m.keySet()+" "+m.values());
                    case 12->mix(m.replace(k,"v1","r")+" "+m.remove(k,"v2")+" "+m.containsValue(val));
                    default->fail(()->{Iterator<Integer> it=m.keySet().iterator();it.next();m.get(it.next());it.next();});
                }
                mix(m.size());
            }
            mix(m.toString());mix(m.hashCode());mix(m.equals(new HashMap<>(m)));
        }
        LinkedHashMap<String,Integer> copy=new LinkedHashMap<>(new TreeMap<>(Map.of("b",2,"a",1,"c",3)));copy.put("a",9);mix(copy.toString());
        LinkedHashSet<String> s=new LinkedHashSet<>();
        for(int i=0;i<100;i++){String x="s"+r.nextInt(12);if(r.nextInt(3)==0)mix(s.remove(x));else mix(s.add(x));}
        mix(s.toString());walk(s.iterator(),r);mix(s.toString());mix(new LinkedHashSet<>(s).equals(s));mix(s.clone().toString());
        return h;
    }

    public static int treeMaps(int seed){
        h=seed;Random r=new Random(seed);
        List<Comparator<Integer>> orders=Arrays.asList(null,Comparator.reverseOrder(),(a,b)->Integer.compare(a/3,b/3),Comparator.nullsFirst(Comparator.naturalOrder()));
        for(int round=0;round<4;round++){
            TreeMap<Integer,String> base=new TreeMap<>(orders.get(round));
            List<NavigableMap<Integer,String>> views=new ArrayList<>();views.add(base);
            for(int i=0;i<300;i++){
                NavigableMap<Integer,String> m=views.get(r.nextInt(views.size()));
                Integer k=round==3&&r.nextInt(8)==0?null:v(r,40),k2=v(r,40);boolean b1=r.nextBoolean(),b2=r.nextBoolean();
                switch(r.nextInt(18)){
                    case 0,1,2->fail(()->mix(m.put(k,"v"+k2)));
                    case 3->fail(()->mix(m.get(k)+" "+m.containsKey(k)));
                    case 4->fail(()->mix(m.remove(k)));
                    case 5->{fail(()->mix(m.firstKey()));fail(()->mix(m.lastKey()));mix(m.firstEntry()+" "+m.lastEntry());}
                    case 6->mix(r.nextBoolean()?m.pollFirstEntry():m.pollLastEntry());
                    case 7->fail(()->mix(m.lowerKey(k)+" "+m.floorKey(k)+" "+m.ceilingKey(k)+" "+m.higherKey(k)));
                    case 8->fail(()->mix(m.lowerEntry(k)+" "+m.floorEntry(k)+" "+m.ceilingEntry(k)+" "+m.higherEntry(k)));
                    case 9->{if(views.size()<6)try{views.add(m.subMap(k,b1,k2,b2));mix(1);}catch(RuntimeException e){mix(e.getClass().getName());}}
                    case 10->{if(views.size()<6)try{views.add(b1?m.headMap(k,b2):m.tailMap(k,b2));mix(2);}catch(RuntimeException e){mix(e.getClass().getName());}}
                    case 11->{if(views.size()<6)views.add(m.descendingMap());}
                    case 12->walk(m.entrySet().iterator(),r);
                    case 13->walk(r.nextBoolean()?m.navigableKeySet().iterator():m.descendingKeySet().iterator(),r);
                    case 14->{for(Map.Entry<Integer,String> e:m.entrySet())if(e.getKey()!=null&&e.getKey()%3==0)e.setValue("s");mix(m.values());}
                    case 15->fail(()->mix(m.headMap(k)+" "+m.tailMap(k2)+" "+m.subMap(k,k2)));
                    case 16->{NavigableSet<Integer> ks=m.navigableKeySet();fail(()->mix(ks.remove(k)+" "+ks.pollFirst()+" "+ks.headSet(k2,true)));fail(()->ks.add(1));}
                    default->{mix(m.size()+" "+m.isEmpty());fail(()->m.firstEntry().setValue("x"));}
                }
            }
            for(NavigableMap<Integer,String> m:views){mix(m.toString());mix(m.hashCode());mix(m.comparator()==null?7:m.comparator().compare(3,9));}
            fail(()->{Iterator<Integer> it=base.keySet().iterator();base.put(99,"n");it.next();});
            TreeMap<Integer,String> cl=(TreeMap<Integer,String>)base.clone();cl.put(-5,"c");mix(cl.size()-base.size());
            mix(new TreeMap<>(base.descendingMap()).toString());
        }
        TreeMap<String,Integer> words=new TreeMap<>();for(String w:new String[]{"the","quick","brown","fox","jumps","over","the","lazy","dog"})words.merge(w,1,Integer::sum);
        mix(words.toString());mix(words.headMap("m").toString());mix(words.descendingMap().tailMap("j",true).toString());
        fail(()->new TreeMap<Object,Integer>().put(new Object(),1));fail(()->new TreeMap<String,Integer>().put(null,1));
        fail(()->new TreeMap<Integer,Integer>().subMap(5,1));fail(()->new TreeMap<Integer,Integer>().headMap(5).put(7,1));
        return h;
    }

    public static int treeSets(int seed){
        h=seed;Random r=new Random(seed);
        TreeSet<Integer> s=new TreeSet<>();for(int i=0;i<60;i++)s.add(r.nextInt(100));
        mix(s.toString());mix(s.first()+" "+s.last()+" "+s.lower(50)+" "+s.floor(50)+" "+s.ceiling(50)+" "+s.higher(50));
        NavigableSet<Integer> sub=s.subSet(20,true,70,false),desc=s.descendingSet(),head=s.headSet(40,true);
        for(int i=0;i<200;i++){
            NavigableSet<Integer> t=switch(r.nextInt(4)){case 0->s;case 1->sub;case 2->desc;default->head;};Integer x=v(r,100);
            switch(r.nextInt(9)){
                case 0,1->fail(()->mix(t.add(x)));
                case 2->mix(t.remove(x));
                case 3->mix(t.pollFirst()+" "+t.pollLast());
                case 4->mix(t.lower(x)+" "+t.floor(x)+" "+t.ceiling(x)+" "+t.higher(x));
                case 5->walk(t.iterator(),r);
                case 6->walk(t.descendingIterator(),r);
                case 7->{int k=r.nextInt(5);mix(t.removeIf(y->y%5==k));}
                default->fail(()->mix(t.headSet(x)+" "+t.tailSet(x,false)+" "+t.reversed()));
            }
            mix(t.size());
        }
        mix(s+" "+sub+" "+desc+" "+head);mix(s.hashCode());mix(s.equals(new HashSet<>(s)));
        TreeSet<String> words=new TreeSet<>(Comparator.comparing(String::length).thenComparing(Comparator.reverseOrder()));
        words.addAll(List.of("pear","fig","banana","kiwi","apple","date","plum"));mix(words.toString());mix(words.getFirst()+words.getLast());
        mix(new TreeSet<>(words).toString());mix(((TreeSet<?>)words.clone()).size());fail(()->new TreeSet<Integer>().first());
        fail(()->new TreeSet<Object>().add(new Object()));fail(()->s.subSet(80,10));
        return h;
    }

    public static int enums(int seed){
        h=seed;Random r=new Random(seed);
        Color[] cs=Color.values();Wide[] ws=Wide.values();
        EnumSet<Color> a=EnumSet.noneOf(Color.class);EnumSet<Wide> b=EnumSet.noneOf(Wide.class);
        EnumMap<Color,Integer> m=new EnumMap<>(Color.class);
        for(int i=0;i<200;i++){
            Color c=cs[r.nextInt(cs.length)];Wide w=ws[r.nextInt(ws.length)];
            switch(r.nextInt(10)){
                case 0,1->mix(a.add(c)+" "+b.add(w));
                case 2->mix(a.remove(c)+" "+b.remove(w));
                case 3->mix(a.contains(c)+" "+b.contains(w)+" "+a.contains(w));
                case 4->{walk(a.iterator(),r);walk(b.iterator(),r);}
                case 5->mix(m.put(c,r.nextInt(5)==0?null:i));
                case 6->mix(m.get(c)+" "+m.remove(cs[r.nextInt(cs.length)])+" "+m.containsKey(c)+" "+m.containsValue(null));
                case 7->{walk(m.keySet().iterator(),r);mix(m.toString());}
                case 8->{for(Map.Entry<Color,Integer> e:m.entrySet())e.setValue(e.getValue()==null?-1:e.getValue()+1);mix(m.values());}
                default->mix(EnumSet.complementOf(a)+" "+EnumSet.complementOf(b).size()+" "+EnumSet.copyOf(a)+" "+b.size());
            }
        }
        mix(a.toString());mix(b.toString());mix(m.toString());
        mix(EnumSet.allOf(Color.class).toString());mix(EnumSet.range(Color.GREEN,Color.MAGENTA).toString());mix(EnumSet.range(Wide.W60,Wide.W70).toString());
        mix(EnumSet.of(Color.BLACK,Color.RED,Color.GREEN,Color.RED).toString());mix(EnumSet.of(Wide.W79,Wide.W0,Wide.W63,Wide.W64,Wide.W1,Wide.W2).toString());
        mix(EnumSet.copyOf(List.of(Color.BLUE,Color.RED)).toString());mix(EnumSet.allOf(Wide.class).containsAll(b));
        mix(a.equals(new HashSet<>(a)));mix(EnumSet.noneOf(Color.class).equals(EnumSet.noneOf(Wide.class)));mix(new EnumMap<>(m).equals(m));
        EnumMap<Wide,String> wm=new EnumMap<>(Map.of(Wide.W69,"x",Wide.W3,"y"));wm.put(Wide.W70,null);mix(wm.toString());mix(wm.size());
        fail(()->EnumSet.copyOf(new ArrayList<Color>()));fail(()->EnumSet.range(Color.BLUE,Color.RED));fail(()->a.add(null));
        fail(()->m.put(null,1));fail(()->new EnumMap<Color,Integer>(new HashMap<Color,Integer>()));
        @SuppressWarnings({"unchecked","rawtypes"}) Set<Object> raw=(Set)a;fail(()->raw.add(Wide.W1));
        @SuppressWarnings({"unchecked","rawtypes"}) Map<Object,Integer> rawm=(Map)m;fail(()->rawm.put(Wide.W1,1));
        fail(()->{Iterator<Color> it=EnumSet.of(Color.RED).iterator();it.remove();});
        return h;
    }
}
