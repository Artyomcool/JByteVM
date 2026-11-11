package p19;
import java.util.*;
public final class Main {
    static final class Range implements Iterable<Integer> {
        final int from, to, step;
        Range(int from, int to, int step) { this.from = from; this.to = to; this.step = step; }
        public Iterator<Integer> iterator() { return new Iterator<>() { int next = from; public boolean hasNext() { return step > 0 ? next < to : next > to; } public Integer next() { if (!hasNext()) throw new NoSuchElementException(); int v = next; next += step; return v; } }; }
    }
    public static String run() {
        StringBuilder s = new StringBuilder();
        for (int v : new Range(0, 20, 3)) s.append(v).append(',');
        for (int v : new Range(5, 0, -2)) s.append(v).append(';');
        List<Integer> list = new ArrayList<>(); for (int i = 0; i < 10; i++) list.add(i);
        for (Iterator<Integer> it = list.iterator(); it.hasNext();) if (it.next() % 3 == 0) it.remove();
        list.removeIf(x -> x == 5);
        ListIterator<Integer> li = list.listIterator(); while (li.hasNext()) { int v = li.next(); if (v == 4) li.add(44); else li.set(v * 10); }
        s.append(' ').append(list);
        try { for (Integer x : list) if (x == 20) list.add(1); } catch (ConcurrentModificationException e) { s.append(" cme"); }
        Map<String, Integer> m = new HashMap<>(); m.put("a", 1); m.put("b", 2); m.put("c", 3);
        m.entrySet().removeIf(e -> e.getValue() == 2); m.replaceAll((k, v) -> v * 100);
        m.computeIfPresent("a", (k, v) -> v + 1); m.computeIfAbsent("d", k -> 4); m.compute("c", (k, v) -> null);
        List<String> keys = new ArrayList<>(m.keySet()); Collections.sort(keys);
        s.append(' ').append(keys).append(m.get("a")).append(m.get("d")).append(m.getOrDefault("c", -1));
        try { new Range(0, 0, 1).iterator().next(); } catch (NoSuchElementException e) { s.append(" nse"); }
        return s.toString();
    }
}
