package p03;
import java.util.*;
import java.util.function.*;
public final class Main {
    interface Event { String name(); }
    static final class Damage implements Event { final int amount; Damage(int a) { amount = a; } public String name() { return "damage"; } }
    static final class Heal implements Event { final int amount; Heal(int a) { amount = a; } public String name() { return "heal"; } }
    static final class Bus {
        final Map<Class<?>, List<Consumer<Object>>> handlers = new HashMap<>();
        @SuppressWarnings("unchecked")
        <E> void on(Class<E> type, Consumer<? super E> handler) { handlers.computeIfAbsent(type, k -> new ArrayList<>()).add(e -> handler.accept((E) e)); }
        int post(Event e) { List<Consumer<Object>> list = handlers.getOrDefault(e.getClass(), List.of()); list.forEach(h -> h.accept(e)); return list.size(); }
    }
    static int hp = 100;
    static final List<String> log = new ArrayList<>();
    static void audit(Event e) { log.add(e.name()); }
    public static String run() {
        Bus bus = new Bus();
        int[] dealt = {0};
        bus.on(Damage.class, d -> hp -= d.amount);
        bus.on(Damage.class, d -> dealt[0] += d.amount);
        bus.on(Heal.class, h -> hp = Math.min(100, hp + h.amount));
        bus.on(Damage.class, Main::audit);
        bus.on(Heal.class, Main::audit);
        Supplier<Event> next = new Supplier<>() { int n; public Event get() { return n++ % 3 == 2 ? new Heal(15) : new Damage(7 * n); } };
        int calls = 0;
        for (int i = 0; i < 9; i++) calls += bus.post(next.get());
        BiFunction<Integer, Integer, Integer> add = Integer::sum;
        Function<Integer, String> fmt = v -> "<" + v + ">";
        UnaryOperator<String> up = s -> s + "!";
        return "hp=" + hp + " dealt=" + dealt[0] + " calls=" + calls + " " + log + " " + fmt.andThen(up).apply(add.apply(2, 3));
    }
}
