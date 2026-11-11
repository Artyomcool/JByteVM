package p24;
import java.util.*;
public final class Main {
    public static String run() {
        Integer a = 127, b = 127, c = 128, d = 128;
        Long big = 5L; Double half = 0.5; Character ch = 'z'; Boolean yes = true;
        List<Integer> list = new ArrayList<>(List.of(5, 1, 4));
        list.remove(Integer.valueOf(1)); list.remove(0);
        Map<Character, Integer> freq = new HashMap<>();
        for (char x : "banana".toCharArray()) freq.merge(x, 1, Integer::sum);
        List<Character> keys = new ArrayList<>(freq.keySet()); Collections.sort(keys);
        StringBuilder s = new StringBuilder();
        s.append(a == b).append(c == d).append(c.equals(d)).append(' ').append(big + half).append(' ').append(ch + 1).append(' ').append(!yes).append(' ');
        s.append(list).append(' ');
        for (char k : keys) s.append(k).append(freq.get(k));
        Integer nothing = null;
        try { int v = nothing; s.append(v); } catch (NullPointerException e) { s.append(" npe"); }
        s.append(' ').append(Integer.valueOf(3).compareTo(7)).append(Double.compare(0.0, -0.0)).append(Integer.valueOf(65).hashCode()).append(Long.valueOf(1L << 40).hashCode());
        s.append(' ').append(Integer.parseInt("-123") + Long.parseLong("9000000000") + Short.parseShort("7")).append(' ').append(Double.valueOf("1e-3")).append(' ').append(Float.parseFloat("3.25f"));
        Object[] objs = {1, 2L, 3.0, 4f, (short) 5, (byte) 6, 'c', false};
        for (Object o : objs) s.append(' ').append(o.getClass().getSimpleName());
        return s.toString();
    }
}
