package p27;
import java.util.*;
import java.util.function.*;
import java.util.stream.*;

/** Broad java.util.stream coverage: every line is compared with HotSpot. */
public final class Main {
    record Mob(String name, int hp, double speed, String kind) {}
    static final List<Mob> MOBS = List.of(new Mob("zombie", 20, 0.23, "undead"), new Mob("skeleton", 20, 0.25, "undead"),
        new Mob("creeper", 20, 0.2, "monster"), new Mob("spider", 16, 0.3, "monster"), new Mob("enderman", 40, 0.3, "monster"),
        new Mob("cow", 10, 0.2, "animal"), new Mob("pig", 10, 0.25, "animal"), new Mob("wither", 300, 0.6, "boss"));

    public static String run() {
        StringBuilder out = new StringBuilder();
        line(out, "basic", () -> MOBS.stream().filter(m -> m.hp() > 15).map(Mob::name).sorted(Comparator.reverseOrder()).collect(Collectors.joining(",", "[", "]")));
        line(out, "toList", () -> Stream.of(3, 1, 2).sorted().toList());
        line(out, "distinct", () -> Stream.of(1, 2, 1, 3, 2, 4).distinct().collect(Collectors.toList()));
        line(out, "limitSkip", () -> Stream.iterate(1, x -> x * 2).skip(3).limit(5).toList());
        line(out, "iterate3", () -> Stream.iterate(1, x -> x < 100, x -> x * 3).toList());
        line(out, "generate", () -> { int[] c = {0}; return Stream.generate(() -> c[0]++).limit(4).toList(); });
        line(out, "flatMap", () -> Stream.of("ab", "cde").flatMap(s -> s.chars().mapToObj(c -> (char) c)).toList());
        line(out, "mapMulti", () -> Stream.of(1, 2, 3).<Integer>mapMulti((x, sink) -> { for (int i = 0; i < x; i++) sink.accept(x); }).toList());
        line(out, "takeDrop", () -> Stream.of(1, 2, 3, 10, 1, 2).takeWhile(x -> x < 5).toList() + " " + Stream.of(1, 2, 3, 10, 1, 2).dropWhile(x -> x < 5).toList());
        line(out, "reduce", () -> Stream.of(1, 2, 3, 4).reduce(0, Integer::sum) + " " + Stream.of(1, 2, 3, 4).reduce(Integer::max) + " " + Stream.<Integer>empty().reduce(Integer::max)
            + " " + Stream.of("a", "bb", "ccc").reduce(0, (n, s) -> n + s.length(), Integer::sum));
        line(out, "minmax", () -> MOBS.stream().min(Comparator.comparingDouble(Mob::speed)).map(Mob::name).orElse("-") + " "
            + MOBS.stream().max(Comparator.comparingInt(Mob::hp)).get().name());
        line(out, "match", () -> MOBS.stream().anyMatch(m -> m.hp() > 100) + " " + MOBS.stream().allMatch(m -> m.hp() > 5) + " " + MOBS.stream().noneMatch(m -> m.name().isEmpty())
            + " " + Stream.empty().allMatch(x -> false));
        line(out, "find", () -> MOBS.stream().filter(m -> m.kind().equals("animal")).findFirst().map(Mob::name) + " " + Stream.empty().findAny());
        line(out, "count", () -> MOBS.stream().filter(m -> m.speed() > 0.24).count() + " " + IntStream.range(0, 1000).count());
        line(out, "peekCount", () -> { List<Integer> seen = new ArrayList<>(); long n = List.of(1, 2, 3).stream().peek(seen::add).count(); return n + " " + seen; });
        line(out, "peekFilter", () -> { List<Integer> seen = new ArrayList<>(); long n = List.of(1, 2, 3).stream().peek(seen::add).filter(x -> x > 1).count(); return n + " " + seen; });
        line(out, "lazy", () -> { List<String> log = new ArrayList<>(); Stream.of("a", "b", "c", "d").peek(x -> log.add("p" + x)).filter(x -> !x.equals("b")).map(x -> { log.add("m" + x); return x; }).limit(2).forEach(x -> log.add("f" + x)); return log; });
        line(out, "toArray", () -> Arrays.toString(Stream.of("x", "y").toArray()) + Arrays.toString(Stream.of("x", "y").toArray(String[]::new)) + Stream.of("q").toArray(String[]::new).getClass().getSimpleName());
        line(out, "collect3", () -> Stream.of("a", "b").collect(StringBuilder::new, StringBuilder::append, StringBuilder::append).toString());
        line(out, "builder", () -> { Stream.Builder<String> b = Stream.builder(); b.add("u").add("v"); b.accept("w"); return b.build().toList(); });
        line(out, "concat", () -> Stream.concat(Stream.of(1, 2), Stream.of(3)).toList() + " " + IntStream.concat(IntStream.of(1), IntStream.range(5, 7)).boxed().toList());
        line(out, "ofNullable", () -> Stream.ofNullable(null).count() + " " + Stream.ofNullable("x").count());
        line(out, "iterator", () -> { Iterator<Integer> it = Stream.of(5, 6).iterator(); StringBuilder s = new StringBuilder(); while (it.hasNext()) s.append(it.next()); return s; });
        line(out, "reuse", () -> { Stream<Integer> s = Stream.of(1); s.count(); return s.count(); });
        line(out, "reuse2", () -> { Stream<Integer> s = Stream.of(1); s.map(x -> x); return s.map(x -> x); });
        line(out, "close", () -> { List<String> log = new ArrayList<>(); try (Stream<Integer> s = Stream.of(1).onClose(() -> log.add("a")).onClose(() -> log.add("b"))) { s.count(); } return log; });
        line(out, "limitNeg", () -> Stream.of(1).limit(-1));
        line(out, "firstNull", () -> Stream.of((Object) null).findFirst());
        line(out, "sortedCmp", () -> MOBS.stream().sorted(Comparator.comparing(Mob::kind).thenComparing(Mob::hp, Comparator.reverseOrder()).thenComparing(Mob::name)).map(Mob::name).toList());
        line(out, "arrays", () -> Arrays.stream(new int[]{5, 3, 9}).map(x -> x * 2).sum() + " " + Arrays.stream(new String[]{"a", "b", "c"}, 1, 3).toList() + " " + Arrays.stream(new double[]{1.5, 2.5}).average());
        // primitive streams
        line(out, "intRange", () -> IntStream.rangeClosed(1, 5).map(x -> x * x).boxed().toList() + " " + IntStream.range(5, 5).count() + " " + IntStream.rangeClosed(Integer.MAX_VALUE - 1, Integer.MAX_VALUE).count());
        line(out, "intOps", () -> IntStream.of(4, 1, 3, 1, 5).distinct().sorted().mapToObj(Integer::toString).collect(Collectors.joining("-")));
        line(out, "intStats", () -> IntStream.of(4, 8, 15, 16, 23, 42).summaryStatistics());
        line(out, "intEmpty", () -> IntStream.empty().max() + " " + IntStream.empty().average() + " " + IntStream.empty().sum() + " " + IntStream.empty().summaryStatistics());
        line(out, "intMinMax", () -> IntStream.of(3, -7, 12).min().getAsInt() + " " + IntStream.of(3, -7, 12).max() + " " + IntStream.of(1, 2).average().getAsDouble());
        line(out, "intOverflow", () -> IntStream.of(Integer.MAX_VALUE, 1).sum() + " " + IntStream.of(Integer.MAX_VALUE, 1).asLongStream().sum());
        line(out, "intIter", () -> IntStream.iterate(1, x -> x + 3).limit(4).toArray().length + Arrays.toString(IntStream.iterate(0, x -> x < 10, x -> x + 4).toArray()));
        line(out, "intReduce", () -> IntStream.range(1, 6).reduce(1, (a, b) -> a * b) + " " + IntStream.range(1, 6).reduce(Math::max));
        line(out, "intFlat", () -> IntStream.range(1, 4).flatMap(x -> IntStream.range(0, x)).boxed().toList());
        line(out, "intMatch", () -> IntStream.range(0, 10).anyMatch(x -> x == 7) + " " + IntStream.range(0, 10).allMatch(x -> x < 10) + " " + IntStream.range(0, 10).noneMatch(x -> x > 3));
        line(out, "intCollect", () -> IntStream.range(0, 4).collect(ArrayList<Integer>::new, ArrayList::add, ArrayList::addAll));
        line(out, "intIterator", () -> { PrimitiveIterator.OfInt it = IntStream.of(7, 8).iterator(); return it.nextInt() + it.next() + "" + it.hasNext(); });
        line(out, "intBuilder", () -> IntStream.builder().add(1).add(2).build().sum());
        line(out, "intToDouble", () -> IntStream.of(1, 2, 3).asDoubleStream().map(x -> x / 4).boxed().toList() + " " + IntStream.of(1, 2).mapToLong(x -> x * 10_000_000_000L).sum());
        line(out, "chars", () -> "hello world".chars().filter(Character::isLetter).mapToObj(c -> String.valueOf((char) c)).distinct().count());
        line(out, "longs", () -> LongStream.rangeClosed(1, 20).reduce(1, (a, b) -> a * b) + " " + LongStream.of(5, 1, 9).sorted().boxed().toList() + " " + LongStream.range(0, 5).mapToInt(x -> (int) x * 3).sum()
            + " " + LongStream.of(1, 2, 3).summaryStatistics() + " " + LongStream.empty().min() + " " + LongStream.range(Long.MAX_VALUE - 2, Long.MAX_VALUE).count());
        line(out, "doubles", () -> DoubleStream.of(0.1, 0.2, 0.3).sum() + " " + DoubleStream.of(0.1, 0.2, 0.3).average() + " " + DoubleStream.of(1e100, 1, -1e100).sum()
            + " " + DoubleStream.of(0.1, 0.2, 0.3).summaryStatistics() + " " + DoubleStream.of(2.5, Double.NaN).max() + " " + DoubleStream.of(-0.0, 0.0).min()
            + " " + DoubleStream.of(3, 1, 2).sorted().boxed().toList() + " " + DoubleStream.iterate(1, x -> x / 2).limit(4).mapToObj(Double::toString).toList()
            + " " + DoubleStream.of(Double.POSITIVE_INFINITY, Double.POSITIVE_INFINITY).sum() + " " + DoubleStream.of(1.7, -1.7).mapToInt(x -> (int) x).boxed().toList()
            + " " + DoubleStream.of(1.25).mapToLong(Math::round).sum());
        line(out, "mapToX", () -> MOBS.stream().mapToInt(Mob::hp).sum() + " " + MOBS.stream().mapToDouble(Mob::speed).max() + " " + MOBS.stream().mapToLong(m -> (long) m.hp() << 33).sum()
            + " " + Stream.of("1,2", "3").flatMapToInt(s -> Arrays.stream(s.split(",")).mapToInt(Integer::parseInt)).sum());
        // collectors
        line(out, "grouping", () -> MOBS.stream().collect(Collectors.groupingBy(Mob::kind, TreeMap::new, Collectors.mapping(Mob::name, Collectors.toList()))));
        line(out, "groupCount", () -> new TreeMap<>(MOBS.stream().collect(Collectors.groupingBy(Mob::hp, Collectors.counting()))));
        line(out, "groupDefault", () -> MOBS.stream().map(Mob::name).collect(Collectors.groupingBy(String::length)));
        line(out, "groupNull", () -> Stream.of("a").collect(Collectors.groupingBy(s -> null)));
        line(out, "partition", () -> MOBS.stream().collect(Collectors.partitioningBy(m -> m.hp() >= 20, Collectors.mapping(Mob::name, Collectors.joining("/")))));
        line(out, "partition1", () -> Stream.of(1, 2, 3, 4).collect(Collectors.partitioningBy(x -> x % 2 == 0)));
        line(out, "toMap", () -> new TreeMap<>(MOBS.stream().collect(Collectors.toMap(Mob::name, Mob::hp))));
        line(out, "toMapMerge", () -> MOBS.stream().collect(Collectors.toMap(Mob::kind, Mob::hp, Integer::sum, TreeMap::new)));
        line(out, "toMapDup", () -> MOBS.stream().collect(Collectors.toMap(Mob::kind, Mob::name)));
        line(out, "toMapHash", () -> Stream.of("pear", "fig", "apple", "kiwi", "banana").collect(Collectors.toMap(s -> s, String::length)));
        line(out, "toSet", () -> new TreeSet<>(Stream.of(3, 1, 3).collect(Collectors.toSet())) + " " + Stream.of("b", "a", "b").collect(Collectors.toCollection(TreeSet::new)));
        line(out, "unmod", () -> { List<Integer> l = Stream.of(1, 2).collect(Collectors.toUnmodifiableList()); try { l.add(3); return "mutable"; } catch (UnsupportedOperationException e) { return "immutable " + l; } });
        line(out, "unmodNull", () -> Stream.of("a", null).collect(Collectors.toUnmodifiableList()));
        line(out, "toListNull", () -> Stream.of("a", null).toList());
        line(out, "summing", () -> MOBS.stream().collect(Collectors.summingInt(Mob::hp)) + " " + MOBS.stream().collect(Collectors.summingDouble(Mob::speed)) + " " + MOBS.stream().collect(Collectors.summingLong(Mob::hp))
            + " " + MOBS.stream().collect(Collectors.averagingInt(Mob::hp)) + " " + MOBS.stream().collect(Collectors.averagingDouble(Mob::speed)) + " " + Stream.<Mob>empty().collect(Collectors.averagingLong(Mob::hp)));
        line(out, "summarizing", () -> MOBS.stream().collect(Collectors.summarizingInt(Mob::hp)) + " " + MOBS.stream().collect(Collectors.summarizingDouble(Mob::speed)).getAverage());
        line(out, "minBy", () -> MOBS.stream().collect(Collectors.minBy(Comparator.comparing(Mob::name))).get().name() + " " + MOBS.stream().collect(Collectors.maxBy(Comparator.comparingInt(Mob::hp))).map(Mob::name)
            + " " + Stream.<String>empty().collect(Collectors.maxBy(Comparator.naturalOrder())));
        line(out, "reducing", () -> MOBS.stream().collect(Collectors.reducing(0, Mob::hp, Integer::sum)) + " " + Stream.of(5, 2).collect(Collectors.reducing(Integer::min)) + " " + Stream.of(5, 2).collect(Collectors.reducing(100, Integer::min)));
        line(out, "andThen", () -> MOBS.stream().map(Mob::name).collect(Collectors.collectingAndThen(Collectors.toList(), List::size)));
        line(out, "filtering", () -> MOBS.stream().collect(Collectors.groupingBy(Mob::kind, TreeMap::new, Collectors.filtering(m -> m.hp() > 15, Collectors.mapping(Mob::name, Collectors.toList())))));
        line(out, "flatMapping", () -> Stream.of("ab", "c").collect(Collectors.flatMapping(s -> s.chars().boxed(), Collectors.toList())));
        line(out, "teeing", () -> MOBS.stream().collect(Collectors.teeing(Collectors.counting(), Collectors.summingInt(Mob::hp), (n, s) -> s / n)));
        line(out, "joining", () -> Stream.of("a", "", "b").collect(Collectors.joining()) + "|" + Stream.<String>empty().collect(Collectors.joining(",", "<", ">")) + "|" + Stream.of("", "").collect(Collectors.joining(",")));
        line(out, "custom", () -> Stream.of(1, 2, 3).collect(Collector.of(() -> new int[1], (a, x) -> a[0] += x, (a, b) -> { a[0] += b[0]; return a; }, a -> "sum=" + a[0])));
        line(out, "customId", () -> Stream.of("z", "y").collect(Collector.of(ArrayList<String>::new, ArrayList::add, (a, b) -> { a.addAll(b); return a; })).toString()
            + Collector.of(ArrayList::new, ArrayList::add, (a, b) -> a).characteristics());
        line(out, "nested", () -> MOBS.stream().collect(Collectors.groupingBy(Mob::kind, TreeMap::new, Collectors.groupingBy(m -> m.hp() > 15, Collectors.summingDouble(Mob::speed)))));
        line(out, "unmodMap", () -> new TreeMap<>(Stream.of("a", "bb").collect(Collectors.toUnmodifiableMap(s -> s, String::length))));
        // optionals
        line(out, "optional", () -> Optional.of(3).map(x -> x * 2).filter(x -> x > 5).orElse(0) + " " + Optional.empty().or(() -> Optional.of("alt")).get() + " " + Optional.ofNullable(null).isEmpty()
            + " " + Optional.of("v").flatMap(v -> Optional.of(v + v)) + " " + Optional.of(1).stream().count() + " " + Optional.of(2).equals(Optional.of(2)) + " " + Optional.of("h").hashCode());
        line(out, "optEmpty", () -> Optional.empty().get());
        line(out, "optThrow", () -> Optional.empty().orElseThrow(() -> new IllegalStateException("none")));
        line(out, "optPrim", () -> OptionalInt.of(4) + " " + OptionalLong.empty() + " " + OptionalDouble.of(0.5).orElse(1) + " " + OptionalInt.of(4).equals(OptionalInt.of(4)) + " " + OptionalDouble.of(Double.NaN).equals(OptionalDouble.of(Double.NaN)));
        line(out, "mapStream", () -> { Map<String, Integer> m = new TreeMap<>(Map.of("a", 1, "b", 2, "c", 3)); return m.entrySet().stream().filter(e -> e.getValue() != 2).map(Map.Entry::getKey).collect(Collectors.joining()); });
        line(out, "lateBind", () -> { List<Integer> l = new ArrayList<>(List.of(1)); Stream<Integer> s = l.stream(); l.add(2); return s.toList(); });
        line(out, "big", () -> IntStream.range(0, 100_000).filter(x -> x % 3 == 0).mapToObj(x -> x).collect(Collectors.groupingBy(x -> x % 10, Collectors.counting())));
        return out.toString();
    }
    static void line(StringBuilder out, String name, Supplier<Object> body) {
        Object r;
        try { r = body.get(); } catch (RuntimeException e) { r = e.getClass().getSimpleName() + ":" + e.getMessage(); }
        out.append(name).append('=').append(r).append('\n');
    }
}
