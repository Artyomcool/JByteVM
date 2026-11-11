package p06;
import java.util.*;
public final class Main {
    record Point(int x, int y) {
        Point { if (x < 0) throw new IllegalArgumentException("negative x"); }
        Point plus(Point o) { return new Point(x + o.x, y + o.y); }
        static Point origin() { return new Point(0, 0); }
    }
    record Named<T>(String name, T value) {}
    public static String run() {
        Point a = new Point(1, 2), b = new Point(3, 4);
        Set<Point> set = new HashSet<>(List.of(a, b, new Point(1, 2)));
        Named<Point> n = new Named<>("sum", a.plus(b));
        String bad; try { new Point(-1, 0); bad = "none"; } catch (IllegalArgumentException e) { bad = e.getMessage(); }
        return a + " " + a.equals(new Point(1, 2)) + " " + (a.hashCode() == new Point(1, 2).hashCode()) + " " + set.size() + " " + n + " " + Point.origin().x() + " " + bad;
    }
}
