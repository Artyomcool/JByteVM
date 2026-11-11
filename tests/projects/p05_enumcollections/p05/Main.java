package p05;
import java.util.*;
public final class Main {
    enum Slot { HEAD, CHEST, LEGS, FEET, HAND }
    public static String run() {
        EnumMap<Slot, String> gear = new EnumMap<>(Slot.class);
        gear.put(Slot.FEET, "boots"); gear.put(Slot.HEAD, "helmet"); gear.put(Slot.HAND, "sword");
        EnumSet<Slot> empty = EnumSet.complementOf(EnumSet.copyOf(gear.keySet()));
        return gear + " " + empty + " " + EnumSet.range(Slot.CHEST, Slot.FEET) + " " + EnumSet.allOf(Slot.class).size();
    }
}
