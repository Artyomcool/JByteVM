package p10;
import java.util.*;
import java.util.function.*;
public final class Main {
    static final class Registry<K extends Comparable<K>, V> {
        final List<K> keys = new ArrayList<>(); final List<V> values = new ArrayList<>();
        void put(K k, V v) { int i = Collections.binarySearch(keys, k); if (i >= 0) values.set(i, v); else { keys.add(-i - 1, k); values.add(-i - 1, v); } }
        V get(K k, V fallback) { int i = Collections.binarySearch(keys, k); return i >= 0 ? values.get(i) : fallback; }
        <R> List<R> map(BiFunction<? super K, ? super V, ? extends R> f) { List<R> r = new ArrayList<>(); for (int i = 0; i < keys.size(); i++) r.add(f.apply(keys.get(i), values.get(i))); return r; }
    }
    static <T extends Comparable<? super T>> T max(Collection<? extends T> c) { T best = null; for (T t : c) if (best == null || t.compareTo(best) > 0) best = t; return best; }
    static double sum(List<? extends Number> list) { double s = 0; for (Number n : list) s += n.doubleValue(); return s; }
    static void fill(List<? super Integer> list, int n) { for (int i = 0; i < n; i++) list.add(i * i); }
    interface Box<T> { T get(); }
    static final class IntBox implements Box<Integer> { public Integer get() { return 42; } }
    @SafeVarargs static <T> List<T> listOf(T... items) { return new ArrayList<>(Arrays.asList(items)); }
    public static String run() {
        Registry<String, Integer> r = new Registry<>();
        r.put("zeta", 1); r.put("alpha", 2); r.put("mid", 3); r.put("alpha", 4);
        List<Number> nums = new ArrayList<>(); fill(nums, 5); nums.add(2.5);
        Box<Integer> box = new IntBox(); @SuppressWarnings("unchecked") Box<Object> raw = (Box<Object>) (Box<?>) box;
        return r.map((k, v) -> k + "=" + v) + " " + r.get("mid", -1) + r.get("none", -1) + " " + max(listOf(3, 9, 2)) + " " + max(listOf("b", "c", "a"))
            + " " + sum(nums) + " " + raw.get() + " " + listOf().size();
    }
}
