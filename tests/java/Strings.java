public class Strings {
    static int touched;
    static class Lazy { static int value = ++touched; }
    static class Named { public int hashCode() { return -1; } }
    static class Printed { public String toString() { return "printed"; } }
    static class NullPrinted { public String toString() { return null; } }
    static class ThrowPrinted { public String toString() { throw new IllegalStateException("failure"); } }
    static class Юникод {}
    static class Seq implements CharSequence {
        public int length() { return 3; }
        public char charAt(int i) { return (char)('x' + i); }
        public CharSequence subSequence(int a, int b) { return "xyz".substring(a,b); }
        public String toString() { return "deliberately different"; }
    }
    static class CollectPrinted {
        public String toString() { collect(); return new String(new char[]{'g','c'}); }
    }
    static StringBuilder reentered;
    static class ReenterPrinted {
        public String toString() { reentered.append("inside:"); return "outside"; }
    }
    static class RangeSeq extends Seq {
        public char charAt(int i) { if (i != 1) throw new IllegalStateException(); return 'Y'; }
    }
    public static native void collect();
    static final String CONSTANT = "constant\0\uD83D\uDE00";
    public static String literal() { return "Hello\0Привет\uD83D\uDE00\uD800x\uDC00"; }
    public static String constant() { return CONSTANT; }
    public static String empty() { return ""; }
    public static String concat() { return "v=" + -123 + ":" + Long.MIN_VALUE + ":" + new Printed() + ":" + (Object)null + ":" + true + ":" + 'Ж'; }
    public static String concatDynamic(int i) { return "value=" + i + "/" + (i + 1); }
    public static String builder() {
        StringBuilder b = new StringBuilder("abc");
        b.append(b).append(new char[]{'Q','R','S'},1,2).append((CharSequence)new Seq(),1,3);
        String snapshot = b.toString();
        b.setCharAt(0,'X'); b.setLength(2); b.setLength(4); b.setCharAt(3,'!');
        return snapshot + ":" + b + ":" + new StringBuilder("A\uD83D\uDE00B").reverse();
    }
    public static String primitiveConcat() {
        return new StringBuilder().append(Integer.MIN_VALUE).append('/').append(Long.MIN_VALUE)
            .append('/').append(Float.MIN_VALUE).append('/').append(Double.MIN_VALUE)
            .append('/').append(-0.0f).append('/').append(Double.POSITIVE_INFINITY).toString();
    }
    public static String nullText() { return new StringBuilder().append(new NullPrinted()).append((CharSequence)null,1,3).toString(); }
    public static String reentryAndRanges() {
        reentered = new StringBuilder("start:");
        reentered.append(new ReenterPrinted());
        return reentered.append('/').append((CharSequence)new RangeSeq(),1,2).toString();
    }
    public static String objectText() { return new Named().toString(); }
    public static String classNames() {
        return Strings.class.getName() + ":" + int[][].class.getName() + ":" + String[].class.getName()
            + ":" + int.class + ":" + RunnableLike.class + ":" + Юникод.class.getName();
    }
    interface RunnableLike { void run(); }
    public static int classSemantics() {
        int bits = 0;
        if (new Object().getClass() == Object.class) bits |= 1;
        if (new int[2].getClass() == int[].class) bits |= 2;
        if (int[][].class.getComponentType() == int[].class && int[].class.getComponentType() == int.class) bits |= 4;
        if (void.class.isPrimitive() && !Integer.class.isPrimitive() && !int.class.isArray()) bits |= 8;
        if (Object.class.isAssignableFrom(String.class) && Object[].class.isAssignableFrom(String[].class)) bits |= 16;
        if (!Object.class.isAssignableFrom(int.class) && !int.class.isAssignableFrom(Integer.class)) bits |= 32;
        if (String.class.isInstance("x") && !String.class.isInstance(null) && String.class.cast("x") == "x") bits |= 64;
        if (RunnableLike.class.getSuperclass() == null && int.class.getSuperclass() == null && int[].class.getSuperclass() == Object.class) bits |= 128;
        if (String.class.getComponentType() == null && String.class.cast(null) == null) bits |= 256;
        if (Class.class == String.class.getClass() && CharSequence.class.isAssignableFrom(String.class)) bits |= 512;
        return bits;
    }
    public static int noInitialization() { Class<?> c = Lazy.class; return touched * 100 + (c == Lazy.class ? 1 : 0) + Lazy.value * 10; }
    public static Class<?> intClass() { return int.class; }
    public static int wrapperTypes() {
        return (Integer.class.getSuperclass() == Number.class ? 1 : 0)
            + (Number.class.getSuperclass() == Object.class ? 2 : 0)
            + (Character.class.getSuperclass() == Object.class ? 4 : 0)
            + (Comparable.class.isAssignableFrom(Integer.class) ? 8 : 0)
            + (java.io.Serializable.class.isAssignableFrom(Class.class) ? 16 : 0)
            + (Byte.TYPE == byte.class && Short.TYPE == short.class && Boolean.TYPE == boolean.class
                && Character.TYPE == char.class && Long.TYPE == long.class && Float.TYPE == float.class
                && Double.TYPE == double.class && Void.TYPE == void.class ? 32 : 0);
    }
    public static int constructors() {
        char[] a = {'a','b','c'};
        String s = new String(a); a[0] = 'z';
        String copy = new String(s); char[] b = s.toCharArray(); b[1] = 'z';
        char[] dst = new char[5]; s.getChars(1,3,dst,2);
        return s.hashCode() + copy.hashCode() + new String(a,1,2).hashCode() + String.valueOf(dst,2,2).hashCode()
            + (new String().isEmpty() ? 1 : 0);
    }
    public static int comparisons() {
        String s = "ab\uD83D\uDE00ab";
        return s.length() + s.charAt(2) + s.compareTo("ab\uD83D\uDE01ab")
            + s.indexOf(0x1f600) * 10 + s.lastIndexOf("ab") * 100 + s.indexOf("",99) * 1000
            + (s.startsWith("ab",4) ? 10000 : 0) + (s.endsWith("ab") ? 100000 : 0)
            + (s.substring(2,4).equals("\uD83D\uDE00") ? 1000000 : 0) + (s.equals(new Object()) ? 10000000 : 0);
    }
    public static int intern() {
        String s = new String(new char[]{'h','e','l','l','o'});
        return (s != "hello" ? 1 : 0) + (s.intern() == "hello" ? 2 : 0)
            + (new String().intern() == "" ? 4 : 0) + ("same" == StringPeer.value() ? 8 : 0);
    }
    public static int errors() {
        int n = 0;
        try { "x".charAt(1); } catch (StringIndexOutOfBoundsException e) { n++; }
        try { "x".substring(1,0); } catch (StringIndexOutOfBoundsException e) { n += 2; }
        try { "x".compareTo((String)null); } catch (NullPointerException e) { n += 4; }
        try { new String((char[])null); } catch (NullPointerException e) { n += 8; }
        try { new StringBuilder(-1); } catch (NegativeArraySizeException e) { n += 16; }
        try { String.class.cast(new Object()); } catch (ClassCastException e) { n += 32; }
        try { String.class.isAssignableFrom(null); } catch (NullPointerException e) { n += 64; }
        try { new StringBuilder().append(new ThrowPrinted()); } catch (IllegalStateException e) { n += e.getMessage().equals("failure") ? 128 : 0; }
        return n;
    }
    public static int builderCapacity() {
        StringBuilder b = new StringBuilder(0); int x = b.capacity();
        b.ensureCapacity(3); x += b.capacity()*10; b.append("abcd"); x += b.capacity()*100;
        Comparable<StringBuilder> c = new StringBuilder("abc");
        return x + new StringBuilder("abc").capacity()*1000 + c.compareTo(new StringBuilder("abd"));
    }
    public static String fmtF(float f) { return String.valueOf(f); }
    public static String fmtD(double d) { return String.valueOf(d); }
    public static String gcText(int n) {
        StringBuilder b = new StringBuilder();
        for (int i=0; i<n; i++) { b.append(new CollectPrinted()); collect(); }
        return b.toString().substring(1);
    }
    public static int stringLength(String s) { return s.length(); }
    public static String identity(String s) { collect(); return s; }
    public static String dynamicIntern(String s) { return s.intern(); }
    public static String edits() {
        StringBuilder b=new StringBuilder("abcd");
        b.insert(2,"XYZ").insert(0,17).insert(b.length(),false).insert(3,new char[]{'q','r','s'},1,2);
        b.insert(1,0.25).insert(2,0.5f).insert(3,1234567890123L).insert(4,(Object)null);
        b.insert(2,(CharSequence)new StringBuilder("hello"),1,4).insert(5,'\ud800');
        b.delete(3,8).deleteCharAt(0).replace(2,5,"--").appendCodePoint(0x1f600);
        b.insert(0,(CharSequence)b,1,4);b.replace(b.length()-2,9999,"!");b.trimToSize();
        return b.toString()+":"+b.capacity();
    }
    public static String replacements() {
        String a=" \0\tababa\u2003\r\n".trim();
        String b=a.replace('a','x').replace("xb","AB").replace("","_");
        String c="aaaaa".replace(new StringBuilder("aa"),new StringBuilder("!"));
        return a+"|"+b+"|"+c+"|"+"ab".repeat(3)+"|"+"".repeat(Integer.MAX_VALUE)+"|"+a.contains(new StringBuilder("aba"));
    }
    public static int editErrors() {
        int n=0;StringBuilder b=new StringBuilder("abc");
        try{b.insert(-1,"x");}catch(IndexOutOfBoundsException e){n++;}
        try{b.deleteCharAt(3);}catch(IndexOutOfBoundsException e){n+=2;}
        try{b.replace(2,1,"x");}catch(IndexOutOfBoundsException e){n+=4;}
        try{b.replace(0,1,null);}catch(NullPointerException e){n+=8;}
        try{b.appendCodePoint(0x110000);}catch(IllegalArgumentException e){n+=16;}
        try{"x".replace(null,"a");}catch(NullPointerException e){n+=32;}
        try{"x".repeat(-1);}catch(IllegalArgumentException e){n+=64;}
        return n;
    }
    public static int cloneArrays() {
        char[] a={'a','\ud800','\udfff'};char[] b=a.clone();b[0]='z';
        long[] c={1,Long.MIN_VALUE,3};long[] d=c.clone();
        Object[] e={a,c,null};Object[] f=e.clone();
        return a[0]+b[0]+b[1]+b[2]+(d[1]==Long.MIN_VALUE?1:0)+(e!=f&&e[0]==f[0]?10:0);
    }
}
class StringPeer { public static String value() { return "same"; } }
