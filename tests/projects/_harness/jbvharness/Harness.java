package jbvharness;
/** Runs pNN.Main.run() the same way on HotSpot and JByteVM; exceptions become text. */
public final class Harness {
    private Harness() {}
    public static String run(String name) {
        try { return String.valueOf(Class.forName(name).getMethod("run").invoke(null)); }
        catch (java.lang.reflect.InvocationTargetException e) { return "EXCEPTION " + describe(e.getCause(), name); }
        catch (Throwable t) { return "HARNESS " + describe(t, name); }
    }
    static String describe(Throwable t, String name) {
        StringBuilder s = new StringBuilder(String.valueOf(t));
        String pkg = name.substring(0, name.lastIndexOf('.') + 1);
        for (StackTraceElement e : t.getStackTrace())
            if (e.getClassName().startsWith(pkg)) { s.append(" @").append(e.getClassName()).append('.').append(e.getMethodName()); break; }
        return s.toString();
    }
    public static void main(String[] args) { System.out.print(run(args[0])); }
}
