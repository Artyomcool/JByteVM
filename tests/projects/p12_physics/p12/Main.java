package p12;
public final class Main {
    static final class Body { double x, y, vx, vy; final double mass; Body(double x, double y, double vx, double vy, double m) { this.x = x; this.y = y; this.vx = vx; this.vy = vy; mass = m; } }
    public static String run() {
        Body[] bodies = { new Body(0, 0, 0, 0, 1000), new Body(100, 0, 0, 3, 1), new Body(-150, 20, 0.5, -2.5, 2), new Body(0, 220, -2, 0, 0.5) };
        double dt = 0.05;
        for (int step = 0; step < 4000; step++) {
            for (Body a : bodies) for (Body b : bodies) {
                if (a == b) continue;
                double dx = b.x - a.x, dy = b.y - a.y, d2 = dx * dx + dy * dy + 1e-3, inv = 1 / (Math.sqrt(d2) * d2);
                a.vx += dx * inv * b.mass * dt; a.vy += dy * inv * b.mass * dt;
            }
            for (Body b : bodies) { b.x += b.vx * dt; b.y += b.vy * dt; }
        }
        double energy = 0, angle = 0;
        for (Body b : bodies) { energy += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy); angle += Math.atan2(b.y, b.x); }
        return bodies[1].x + " " + bodies[1].y + " " + energy + " " + angle + " " + Math.sin(1e6) + " " + Math.pow(1.0001, 10000) + " " + Math.round(-2.5) + " " + Math.floorMod(-7, 3) + " " + (float) Math.cbrt(27) + " " + Math.hypot(3, 4);
    }
}
