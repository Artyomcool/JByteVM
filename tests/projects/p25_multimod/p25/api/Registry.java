package p25.api;
import java.util.*;
public final class Registry {
    private final List<Mod> mods = new ArrayList<>();
    public void add(Mod m) { mods.add(m); }
    public List<Mod> mods() { return Collections.unmodifiableList(mods); }
}
