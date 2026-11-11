package java.lang;
public final class Boolean implements java.io.Serializable, Comparable<Boolean> {
    @SuppressWarnings("unchecked") public static final Class<Boolean> TYPE=(Class<Boolean>)jbv.runtime.Support.primitive('Z');
    public static final Boolean TRUE=new Boolean(true), FALSE=new Boolean(false);
    private final boolean value;
    public Boolean(boolean value) { this.value=value; }
    public Boolean(String value) { this.value=parseBoolean(value); }
    public static Boolean valueOf(boolean value) { return value?TRUE:FALSE; }
    public static Boolean valueOf(String value) { return valueOf(parseBoolean(value)); }
    public static boolean parseBoolean(String s) {
        return s!=null && s.length()==4 && (s.charAt(0)|32)=='t' && (s.charAt(1)|32)=='r' && (s.charAt(2)|32)=='u' && (s.charAt(3)|32)=='e';
    }
    public boolean booleanValue() { return value; }
    public boolean equals(Object o) { return o instanceof Boolean && value==((Boolean)o).value; }
    public int hashCode() { return hashCode(value); }
    public static int hashCode(boolean value) { return value?1231:1237; }
    public int compareTo(Boolean other) { return compare(value,other.value); }
    public static int compare(boolean a,boolean b) { return a==b?0:a?1:-1; }
    public String toString() { return toString(value); }
    public static String toString(boolean value) { return value?"true":"false"; }
    public static boolean logicalAnd(boolean a,boolean b) { return a&b; }
    public static boolean logicalOr(boolean a,boolean b) { return a|b; }
    public static boolean logicalXor(boolean a,boolean b) { return a^b; }
}
