package p23;
public final class Main {
    public static String run() {
        int total = 0;
        for (int i = 0; i < 10; i++) total += Host.hostClamp(Host.hostScore(i), 5, 20);
        return "total=" + total + " direct=" + Host.hostScore(100) + " clamp=" + Host.hostClamp(-5, 0, 9);
    }
}
