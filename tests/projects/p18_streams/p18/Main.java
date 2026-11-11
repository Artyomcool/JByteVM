package p18;
import java.util.*;
import java.util.stream.*;
public final class Main {
    public static String run() {
        List<String> names = List.of("zombie", "skeleton", "creeper", "spider", "enderman");
        String joined = names.stream().filter(n -> n.length() > 6).map(String::toUpperCase).sorted().collect(Collectors.joining(","));
        int total = IntStream.rangeClosed(1, 100).filter(i -> i % 7 == 0).sum();
        Map<Integer, Long> byLength = names.stream().collect(Collectors.groupingBy(String::length, TreeMap::new, Collectors.counting()));
        Optional<String> longest = names.stream().max(Comparator.comparingInt(String::length));
        return joined + " " + total + " " + byLength + " " + longest.orElse("-");
    }
}
