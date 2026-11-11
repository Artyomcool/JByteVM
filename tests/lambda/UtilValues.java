import java.util.*;
import java.util.function.*;
/** Arrays, Collections, Random, Comparator and Math scenarios hashed for HotSpot comparison. */
public class UtilValues {
    static int h;
    static void mix(int v){h=h*31+v;}
    static void mix(String s){mix(s.hashCode());}
    static void mix(boolean b){mix(b?1:0);}
    static void mix(long v){mix((int)(v^(v>>>32)));}
    static void mix(double v){mix(Double.doubleToRawLongBits(v));}
    static void fail(Runnable r){try{r.run();mix(0);}catch(RuntimeException e){mix(e.getClass().getName());}}

    public static int arrays(int seed){
        h=seed;Random r=new Random(seed);
        int[] a=new int[200];for(int i=0;i<a.length;i++)a[i]=r.nextInt(50)-25;
        int[] b=a.clone();Arrays.sort(b);mix(Arrays.hashCode(b));mix(Arrays.toString(Arrays.copyOf(b,7)));
        for(int k=-30;k<30;k+=3)mix(Arrays.binarySearch(b,k)<0?-1:b[Arrays.binarySearch(b,k)]);
        Arrays.sort(a,10,90);mix(Arrays.hashCode(a));
        long[] l=new long[64];for(int i=0;i<l.length;i++)l[i]=r.nextLong();Arrays.sort(l);mix(Arrays.hashCode(l));mix(Arrays.binarySearch(l,l[17]));
        double[] d={3.5,-0.0,0.0,Double.NaN,-1e300,Double.POSITIVE_INFINITY,1.0/3,-7,Double.MIN_VALUE};
        Arrays.sort(d);mix(Arrays.toString(d));mix(Arrays.hashCode(d));mix(Arrays.binarySearch(d,0.0));mix(Arrays.binarySearch(d,Double.NaN));
        float[] f={2f,-0f,0f,Float.NaN,-3f,1e30f};Arrays.sort(f);mix(Arrays.toString(f));mix(Arrays.equals(f,f.clone())?1:0);
        char[] c="hello, world".toCharArray();Arrays.sort(c);mix(new String(c));mix(Arrays.toString(c));
        short[] s={5,-3,9,0};byte[] y={7,-128,127,0};Arrays.sort(s);Arrays.sort(y);mix(Arrays.toString(s)+Arrays.toString(y));
        boolean[] z=new boolean[5];Arrays.fill(z,1,3,true);mix(Arrays.toString(z));mix(Arrays.hashCode(z));
        int[] filled=new int[6];Arrays.fill(filled,9);Arrays.fill(filled,2,4,-1);mix(Arrays.toString(filled));
        mix(Arrays.toString(Arrays.copyOfRange(filled,4,9)));mix(Arrays.equals(filled,new int[]{9,9,-1,-1,9,9})?1:0);
        String[] w={"pear","Apple","fig","banana","apple","Fig"};
        String[] w2=w.clone();Arrays.sort(w2);mix(Arrays.toString(w2));
        Arrays.sort(w2,Comparator.comparing(x->x.charAt(x.length()-1)));mix(Arrays.toString(w2));
        Arrays.sort(w2,Comparator.comparingInt(String::length).thenComparing(Comparator.reverseOrder()));mix(Arrays.toString(w2));
        Arrays.sort(w,1,5);mix(Arrays.toString(w));mix(Arrays.binarySearch(new String[]{"a","c","e"},"d"));
        Object[] copy=Arrays.copyOf(w,8);mix(copy.getClass().getName());mix(Arrays.toString(copy));
        Number[] nums=Arrays.copyOf(new Integer[]{1,2},3,Number[].class);mix(nums.getClass().getName());
        Object[] deep={new int[]{1,2},new String[]{"x",null},null,new double[]{0.5},new Object[]{new long[]{3}}};
        mix(Arrays.deepToString(deep));mix(Arrays.deepHashCode(deep));mix(Arrays.deepEquals(deep,deep.clone())?1:0);
        Object[] self=new Object[2];self[0]=self;self[1]="v";mix(Arrays.deepToString(self));
        List<String> as=Arrays.asList("a","b","c");as.set(1,"B");mix(as.toString());mix(as.indexOf("c"));
        fail(()->as.add("d"));fail(()->Arrays.fill(new int[3],2,1,0));fail(()->Arrays.copyOfRange(new int[3],4,5));
        fail(()->Arrays.sort(new int[3],0,4));fail(()->Arrays.copyOf(new int[1],-1));fail(()->Arrays.fill(new Integer[1],"s"));
        int[] sq=new int[8];Arrays.setAll(sq,i->i*i);mix(Arrays.toString(sq));
        double[] half=new double[4];Arrays.setAll(half,i->i/2.0);mix(Arrays.toString(half));
        mix(Arrays.toString((int[])null));mix(Arrays.hashCode((Object[])null));
        return h;
    }

    public static int collections(int seed){
        h=seed;Random r=new Random(seed);
        List<Integer> a=new ArrayList<>();for(int i=0;i<40;i++)a.add(r.nextInt(100));
        Collections.sort(a);mix(a.hashCode());mix(Collections.binarySearch(a,a.get(13)));mix(Collections.binarySearch(a,1000));
        Collections.reverse(a);mix(a.hashCode());Collections.shuffle(a,new Random(seed));mix(a.toString());
        Collections.rotate(a,7);mix(a.hashCode());Collections.rotate(a,-3);mix(a.hashCode());Collections.swap(a,0,5);mix(a.hashCode());
        mix(Collections.max(a));mix(Collections.min(a));mix(Collections.max(a,Comparator.reverseOrder()));
        mix(Collections.frequency(a,a.get(0)));mix(Collections.indexOfSubList(a,a.subList(10,13)));mix(Collections.lastIndexOfSubList(a,List.of(-1)));
        Collections.replaceAll(a,a.get(0),-5);mix(a.hashCode());
        List<Integer> dst=new ArrayList<>(Collections.nCopies(45,0));Collections.copy(dst,a);mix(dst.hashCode());
        Collections.fill(dst,3);mix(dst.hashCode());mix(Collections.disjoint(a,dst)?1:0);
        Collections.addAll(dst,1,2,3);mix(dst.size());
        List<String> v=Collections.unmodifiableList(new ArrayList<>(List.of("x","y","z")));
        mix(v.toString());mix(v.subList(1,3).toString());mix(v.equals(List.of("x","y","z"))?1:0);mix(v.hashCode());
        fail(()->v.add("w"));fail(()->v.set(0,"q"));fail(()->v.iterator().remove());fail(()->v.clear());fail(()->v.sort(null));
        fail(()->v.listIterator().set("q"));fail(()->v.removeIf(x->true));
        Map<String,Integer> m=new HashMap<>();m.put("one",1);m.put("two",2);
        Map<String,Integer> um=Collections.unmodifiableMap(m);m.put("three",3);
        mix(um.size());mix(um.get("three"));mix(um.equals(m)?1:0);mix(um.hashCode());
        int sum=0;for(Map.Entry<String,Integer> e:um.entrySet())sum+=e.getKey().length()*e.getValue();mix(sum);
        fail(()->um.put("x",1));fail(()->um.entrySet().iterator().next().setValue(9));fail(()->um.putIfAbsent("one",5));
        fail(()->um.remove("one"));fail(()->um.keySet().remove("one"));fail(()->um.values().clear());
        Set<Integer> us=Collections.unmodifiableSet(new HashSet<>(List.of(1,2,3)));mix(us.hashCode());mix(us.equals(Set.of(3,2,1))?1:0);mix(us.contains(2)?1:0);
        fail(()->us.add(4));fail(()->us.retainAll(List.of()));
        Collection<Integer> uc=Collections.unmodifiableCollection(a);mix(uc.size());fail(()->uc.remove((Object)a.get(0)));
        mix(Collections.emptyList().size());mix(Collections.emptySet().contains(null)?1:0);mix(Collections.emptyMap().containsKey(null)?1:0);
        mix(Collections.emptyIterator().hasNext()?1:0);fail(()->Collections.emptyList().add(null));
        mix(Collections.singletonList(null).toString());mix(Collections.singleton(7).hashCode());mix(Collections.singletonMap("k",null).toString());
        List<String> copies=Collections.nCopies(4,"ab");mix(copies.toString());mix(copies.hashCode());mix(copies.indexOf("ab"));
        fail(()->Collections.nCopies(-1,"x"));fail(()->copies.set(0,"z"));fail(()->Collections.max(new ArrayList<Integer>()));
        fail(()->Collections.copy(new ArrayList<Integer>(),List.of(1)));
        List<Integer> sorted=new ArrayList<>(List.of(5,3,9,1));Collections.sort(sorted,Collections.reverseOrder(Comparator.<Integer>naturalOrder()));mix(sorted.toString());
        return h;
    }

    public static int random(int seed){
        h=seed;Random r=new Random(seed*0x9E3779B9L);
        for(int i=0;i<40;i++){mix(r.nextInt());mix(r.nextInt(1+i*977));mix(r.nextInt(64));mix(r.nextLong());}
        for(int i=0;i<20;i++){mix(r.nextDouble());mix(Float.floatToIntBits(r.nextFloat()));mix(r.nextBoolean()?1:0);mix(r.nextGaussian());}
        for(int i=0;i<20;i++){mix(r.nextInt(-5,17));mix(r.nextInt(Integer.MIN_VALUE,Integer.MAX_VALUE));mix(r.nextInt(-1<<30,1<<30));mix(r.nextInt(0,1<<20));}
        byte[] bytes=new byte[13];r.nextBytes(bytes);mix(Arrays.hashCode(bytes));
        r.setSeed(seed);mix(r.nextGaussian());mix(r.nextInt());
        fail(()->new Random(1).nextInt(0));fail(()->new Random(1).nextInt(5,5));
        return h;
    }

    public static int comparators(int seed){
        h=seed;
        List<String> w=new ArrayList<>(List.of("kiwi","fig","apple","Banana","date","cherry","fig",""));
        w.sort(Comparator.comparing(String::length));mix(w.toString());
        w.sort(Comparator.comparing(String::length,Comparator.reverseOrder()));mix(w.toString());
        w.sort(Comparator.comparingInt(String::length).thenComparing(Function.identity()));mix(w.toString());
        w.sort(Comparator.<String>comparingLong(s->s.hashCode()).reversed());mix(w.toString());
        w.sort(Comparator.<String>comparingDouble(s->-s.length()).thenComparingInt(s->s.charAt(0)*0+seed%3).thenComparing(String::toString,Comparator.reverseOrder()));mix(w.toString());
        w.add(null);w.add(2,null);
        w.sort(Comparator.nullsFirst(Comparator.<String>naturalOrder()));mix(w.toString());
        w.sort(Comparator.nullsLast(Comparator.<String>reverseOrder()));mix(w.toString());
        w.sort(Comparator.nullsFirst(null));mix(w.toString());
        w.removeIf(Objects::isNull);w.sort(Comparator.<String>comparingInt(String::length).thenComparingLong(s->s.isEmpty()?0:s.charAt(0)).thenComparingDouble(s->s.length()*0.5));mix(w.toString());
        return h;
    }

    public static int math(int seed){
        h=seed;Random r=new Random(seed);
        double[] special={0.0,-0.0,1,-1,0.5,-0.5,2,Math.PI,-Math.PI/2,Math.E,1e-300,-1e-310,1e300,Double.MAX_VALUE,Double.MIN_VALUE,
            Double.MIN_NORMAL,Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY,710,-746,1e22,3.0e9,0.7,1-1e-16};
        for(int i=0;i<special.length+300;i++){
            double x=i<special.length?special[i]:(i&1)==0?(r.nextDouble()-0.5)*StrictMath.pow(10,r.nextInt(40)-20):Double.longBitsToDouble(r.nextLong());
            double y=i<special.length?special[(i*7)%special.length]:(r.nextDouble()-0.3)*8;
            mix(StrictMath.sin(x));mix(StrictMath.cos(x));mix(StrictMath.tan(x));mix(StrictMath.asin(x));mix(StrictMath.acos(x));mix(StrictMath.atan(x));
            mix(StrictMath.exp(x));mix(StrictMath.log(x));mix(StrictMath.log10(x));mix(StrictMath.log1p(x));mix(StrictMath.expm1(x));mix(StrictMath.cbrt(x));
            mix(StrictMath.sinh(x));mix(StrictMath.cosh(x));mix(StrictMath.tanh(x));mix(StrictMath.atan2(y,x));mix(StrictMath.pow(x,y));mix(StrictMath.pow(y,x));mix(StrictMath.hypot(x,y));
            mix(StrictMath.toRadians(x));mix(StrictMath.toDegrees(x));
        }
        // StrictMath, not Math: HotSpot's Math intrinsics may differ by 1 ulp (JByteVM's Math is StrictMath).
        return h;
    }
}
