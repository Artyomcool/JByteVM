package java.util.regex;
import java.util.Map;
public interface MatchResult {
    int start();
    int start(int group);
    int end();
    int end(int group);
    String group();
    String group(int group);
    int groupCount();
    default int start(String name) { return start(number(this,name)); }
    default int end(String name) { return end(number(this,name)); }
    default String group(String name) { return group(number(this,name)); }
    default Map<String,Integer> namedGroups() { throw new UnsupportedOperationException("namedGroups()"); }
    default boolean hasMatch() { throw new UnsupportedOperationException("hasMatch()"); }
    private static int number(MatchResult r, String name) {
        java.util.Objects.requireNonNull(name,"Group name");
        Integer n=r.namedGroups().get(name);
        if(n==null)throw new IllegalArgumentException("No group with name <"+name+">");
        return n;
    }
}
