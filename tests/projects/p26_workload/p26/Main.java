package p26;
import java.util.*;
public final class Main {
    public static String run() {
        int n = 2_000_000; boolean[] composite = new boolean[n + 1]; int primes = 0; long sum = 0;
        for (int i = 2; i <= n; i++) { if (composite[i]) continue; primes++; sum += i; for (long j = (long) i * i; j <= n; j += i) composite[(int) j] = true; }
        HashMap<Integer, Integer> m = new HashMap<>(); int x = 1;
        for (int i = 0; i < 200_000; i++) { x = x * 1103515245 + 12345; m.merge((x >>> 8) & 0xffff, 1, Integer::sum); }
        StringBuilder sb = new StringBuilder(); for (int i = 0; i < 50_000; i++) sb.append(i % 10);
        ArrayList<Integer> list = new ArrayList<>(); for (int i = 0; i < 100_000; i++) list.add((i * 7919) % 100_003); Collections.sort(list);
        double acc = 0; for (int i = 1; i < 300_000; i++) acc += Math.sqrt(i) / i;
        return primes + " " + sum + " " + m.size() + " " + sb.length() + " " + list.get(50_000) + " " + acc;
    }
}
