package p25;
import java.util.*;
import p25.api.*;
public final class Main {
    public static String run() {
        Registry registry = new Registry();
        new p25.mods.Weather().register(registry);
        new p25.mods.Economy().register(registry);
        StringBuilder s = new StringBuilder();
        for (int tick = 0; tick < 5; tick++) for (Mod m : registry.mods()) s.append(m.id()).append(':').append(m.tick(tick)).append(' ');
        return s.append(registry.mods().size()).toString();
    }
}
