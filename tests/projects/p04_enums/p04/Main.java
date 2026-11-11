package p04;
import java.util.*;
public final class Main {
    enum Biome {
        DESERT(40, false), FOREST(20, true), TUNDRA(-15, false) { @Override String describe() { return "cold " + super.describe(); } }, OCEAN(10, true);
        final int temperature; final boolean wet;
        Biome(int t, boolean w) { temperature = t; wet = w; }
        String describe() { return name() + "@" + temperature; }
    }
    enum Direction { N, E, S, W; Direction turn() { return values()[(ordinal() + 1) % values().length]; } }
    static int rain(Biome b) {
        switch (b) { case DESERT: return 0; case FOREST: return 3; case OCEAN: return 5; default: return 1; }
    }
    public static String run() {
        StringBuilder s = new StringBuilder();
        for (Biome b : Biome.values()) s.append(b).append(':').append(b.ordinal()).append(':').append(rain(b)).append(':').append(b.describe()).append(' ');
        Direction d = Direction.N; for (int i = 0; i < 6; i++) d = d.turn();
        s.append(d).append(' ').append(Biome.valueOf("OCEAN").wet).append(' ').append(Biome.TUNDRA.getClass() == Biome.class).append(' ').append(Biome.TUNDRA.getDeclaringClass() == Biome.class);
        s.append(' ').append(Biome.DESERT.compareTo(Biome.OCEAN));
        try { Biome.valueOf("SWAMP"); } catch (IllegalArgumentException e) { s.append(" bad:").append(e.getMessage()); }
        return s.toString();
    }
}
