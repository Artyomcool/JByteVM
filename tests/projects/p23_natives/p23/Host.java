package p23;
/** Implemented by the host application (tests/run_projects.py binds them). */
public final class Host {
    public static native int hostScore(int value);
    public static native int hostClamp(int value, int low, int high);
}
