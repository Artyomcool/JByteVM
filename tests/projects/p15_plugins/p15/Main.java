package p15;
import java.lang.annotation.*;
import java.lang.reflect.*;
import java.util.*;
public final class Main {
    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.METHOD) @interface Command { String value(); int priority() default 5; String[] aliases() default {}; }
    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.TYPE) @interface Plugin { String id(); }
    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.FIELD) @interface Config { String key(); }
    @Plugin(id = "greeter")
    public static final class Greeter {
        @Config(key = "greeting") public String greeting = "hi";
        @Config(key = "times") public int times = 1;
        @Command(value = "greet", priority = 1, aliases = {"g", "hello"}) public String greet(String who) { return (greeting + " " + who + " ").repeat(times).trim(); }
        @Command("count") public int count(String who) { return who.length(); }
        public String notACommand() { return "x"; }
        private String hidden() { return "hidden"; }
    }
    public static String run() throws Exception {
        Class<?> type = Class.forName("p15.Main$Greeter");
        Object plugin = type.getConstructor().newInstance();
        Map<String, Object> config = new HashMap<>(); config.put("greeting", "hello"); config.put("times", 2);
        for (Field f : type.getFields()) { Config c = f.getAnnotation(Config.class); if (c != null) f.set(plugin, config.get(c.key())); }
        List<Method> commands = new ArrayList<>();
        for (Method m : type.getDeclaredMethods()) if (m.isAnnotationPresent(Command.class)) commands.add(m);
        commands.sort(Comparator.comparingInt((Method m) -> m.getAnnotation(Command.class).priority()).thenComparing(Method::getName));
        StringBuilder s = new StringBuilder(type.getAnnotation(Plugin.class).id()).append(':');
        for (Method m : commands) { Command c = m.getAnnotation(Command.class); s.append(c.value()).append(Arrays.toString(c.aliases())).append('=').append(m.invoke(plugin, "bob")).append(' '); }
        Method hidden = type.getDeclaredMethod("hidden"); hidden.setAccessible(true);
        s.append(hidden.invoke(plugin)).append(' ').append(Modifier.isPrivate(hidden.getModifiers()));
        try { type.getMethod("missing"); } catch (NoSuchMethodException e) { s.append(" nsme"); }
        s.append(' ').append(commands.get(0).getParameters()[0].getName());
        return s.toString();
    }
}
