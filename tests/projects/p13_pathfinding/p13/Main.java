package p13;
import java.util.*;
public final class Main {
    static final String[] MAP = {
        "S....#....",
        ".##..#.##.",
        ".#...#..#.",
        ".#.###..#.",
        "...#....#G",
        ".#.#.####.",
        ".#...#....",
    };
    public static String run() {
        int h = MAP.length, w = MAP[0].length(), start = 0, goal = 0;
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { char c = MAP[y].charAt(x); if (c == 'S') start = y * w + x; if (c == 'G') goal = y * w + x; }
        int[] dist = new int[w * h]; Arrays.fill(dist, Integer.MAX_VALUE); dist[start] = 0;
        int gx = goal % w, gy = goal / w;
        PriorityQueue<int[]> open = new PriorityQueue<>(Comparator.comparingInt((int[] a) -> a[0]).thenComparingInt(a -> a[1]));
        open.add(new int[]{Math.abs(gx) + Math.abs(gy), start});
        int expanded = 0;
        while (!open.isEmpty()) {
            int[] cur = open.poll(); int p = cur[1];
            if (p == goal) break;
            expanded++;
            int px = p % w, py = p / w;
            int[][] dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
            for (int[] d : dirs) {
                int nx = px + d[0], ny = py + d[1];
                if (nx < 0 || ny < 0 || nx >= w || ny >= h || MAP[ny].charAt(nx) == '#') continue;
                int q = ny * w + nx, nd = dist[p] + 1;
                if (nd < dist[q]) { dist[q] = nd; open.add(new int[]{nd + Math.abs(gx - nx) + Math.abs(gy - ny), q}); }
            }
        }
        ArrayDeque<Integer> bfs = new ArrayDeque<>(); bfs.add(start); boolean[] seen = new boolean[w * h]; seen[start] = true; int reach = 0;
        while (!bfs.isEmpty()) { int p = bfs.poll(); reach++; for (int q : new int[]{p - 1, p + 1, p - w, p + w}) if (q >= 0 && q < w * h && !seen[q] && MAP[q / w].charAt(q % w) != '#' && Math.abs(q % w - p % w) <= 1) { seen[q] = true; bfs.add(q); } }
        return "dist=" + dist[goal] + " expanded=" + expanded + " reach=" + reach;
    }
}
