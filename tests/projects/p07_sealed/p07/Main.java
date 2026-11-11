package p07;
public final class Main {
    sealed interface Shape permits Circle, Rect, Tri {}
    static final class Circle implements Shape { final double r; Circle(double r) { this.r = r; } }
    static final class Rect implements Shape { final double w, h; Rect(double w, double h) { this.w = w; this.h = h; } }
    static final class Tri implements Shape { final double b, h; Tri(double b, double h) { this.b = b; this.h = h; } }
    static double area(Shape s) {
        return switch (s) {
            case Circle c -> Math.PI * c.r * c.r;
            case Rect r when r.w == r.h -> r.w * r.w;
            case Rect r -> r.w * r.h;
            case Tri t -> t.b * t.h / 2;
        };
    }
    public static String run() {
        Shape[] shapes = {new Circle(1), new Rect(2, 2), new Rect(2, 3), new Tri(3, 4)};
        StringBuilder s = new StringBuilder();
        for (Shape x : shapes) s.append(area(x)).append(' ');
        return s.toString();
    }
}
