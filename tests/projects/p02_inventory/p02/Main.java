package p02;
import java.util.*;
public final class Main {
    static final class Item {
        final String name; final int weight; final int value;
        Item(String name, int weight, int value) { this.name = name; this.weight = weight; this.value = value; }
        public String toString() { return name + "(" + weight + "kg," + value + "g)"; }
    }
    static final class Inventory {
        final List<Item> items = new ArrayList<>();
        final Map<String, Integer> counts = new HashMap<>();
        final int capacity;
        Inventory(int capacity) { this.capacity = capacity; }
        int weight() { int w = 0; for (Item i : items) w += i.weight; return w; }
        boolean add(Item item) {
            if (weight() + item.weight > capacity) return false;
            items.add(item); counts.merge(item.name, 1, Integer::sum); return true;
        }
        List<Item> sorted(Comparator<Item> order) { List<Item> copy = new ArrayList<>(items); copy.sort(order); return copy; }
    }
    public static String run() {
        Inventory inv = new Inventory(50);
        String[] names = {"sword", "shield", "potion", "potion", "gem", "anvil", "rope", "potion"};
        int[] weights = {10, 15, 1, 1, 1, 40, 3, 1};
        int[] values = {100, 80, 25, 25, 500, 10, 5, 25};
        StringBuilder log = new StringBuilder();
        for (int i = 0; i < names.length; i++) log.append(inv.add(new Item(names[i], weights[i], values[i])) ? '+' : '-');
        List<Item> byValue = inv.sorted(Comparator.comparingInt((Item i) -> i.value).reversed().thenComparing(i -> i.name));
        List<String> keys = new ArrayList<>(inv.counts.keySet()); Collections.sort(keys);
        StringBuilder counts = new StringBuilder();
        for (String k : keys) counts.append(k).append('=').append(inv.counts.get(k)).append(';');
        return log + " w=" + inv.weight() + " " + byValue + " " + counts;
    }
}
