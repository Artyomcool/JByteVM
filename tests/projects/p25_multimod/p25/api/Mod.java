package p25.api;
public interface Mod {
    String id();
    String tick(int tick);
    default void register(Registry r) { r.add(this); }
}
