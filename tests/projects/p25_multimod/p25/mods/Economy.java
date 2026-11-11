package p25.mods;
import p25.api.Mod;
public final class Economy implements Mod {
    private long gold = 100;
    public String id() { return "economy"; }
    public String tick(int t) { gold = gold * 105 / 100 + t; return Long.toString(gold); }
}
