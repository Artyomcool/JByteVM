package p25.mods;
import p25.api.Mod;
public final class Weather implements Mod {
    private final String[] states = {"sun", "rain", "storm"};
    public String id() { return "weather"; }
    public String tick(int t) { return states[(t * 7 + 1) % states.length]; }
}
