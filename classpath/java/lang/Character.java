package java.lang;
public final class Character implements java.io.Serializable, Comparable<Character> {
    public static final char MIN_VALUE=0, MAX_VALUE=65535, MIN_HIGH_SURROGATE=0xd800, MAX_HIGH_SURROGATE=0xdbff,
        MIN_LOW_SURROGATE=0xdc00, MAX_LOW_SURROGATE=0xdfff, MIN_SURROGATE=0xd800, MAX_SURROGATE=0xdfff;
    public static final int SIZE=16, BYTES=2, MIN_RADIX=2, MAX_RADIX=36, MIN_CODE_POINT=0, MAX_CODE_POINT=0x10ffff, MIN_SUPPLEMENTARY_CODE_POINT=65536;
    @SuppressWarnings("unchecked") public static final Class<Character> TYPE=(Class<Character>)jbv.runtime.Support.primitive('C');
    private final char value;
    private static final Character[] cache=new Character[128];
    public Character(char value) { this.value=value; }
    public static Character valueOf(char value) { if(value>=128)return new Character(value); Character c=cache[value]; if(c==null)cache[value]=c=new Character(value); return c; }
    public char charValue() { return value; }
    public boolean equals(Object o) { return o instanceof Character && value==((Character)o).value; }
    public int hashCode() { return value; }
    public static int hashCode(char value) { return value; }
    public int compareTo(Character other) { return compare(value,other.value); }
    public static int compare(char a,char b) { return a-b; }
    public String toString() { return String.valueOf(value); }
    public static String toString(char value) { return String.valueOf(value); }
    public static String toString(int codePoint) { return new String(toChars(codePoint)); }
    public static boolean isHighSurrogate(char c) { return c>=0xd800 && c<=0xdbff; }
    public static boolean isLowSurrogate(char c) { return c>=0xdc00 && c<=0xdfff; }
    public static boolean isSurrogate(char c) { return c>=0xd800 && c<=0xdfff; }
    public static boolean isSurrogatePair(char a,char b) { return isHighSurrogate(a)&&isLowSurrogate(b); }
    public static int toCodePoint(char a,char b) { return 65536+((a-0xd800)<<10)+(b-0xdc00); }
    public static char highSurrogate(int c) { return (char)(0xd800+((c-65536)>>>10)); }
    public static char lowSurrogate(int c) { return (char)(0xdc00+((c-65536)&1023)); }
    public static boolean isValidCodePoint(int c) { return c>=0 && c<=0x10ffff; }
    public static boolean isBmpCodePoint(int c) { return c>=0 && c<65536; }
    public static boolean isSupplementaryCodePoint(int c) { return c>=65536 && c<=0x10ffff; }
    public static int charCount(int c) { return c>=65536?2:1; }
    public static char[] toChars(int c) { if(!isValidCodePoint(c))throw new IllegalArgumentException(); return c<65536?new char[]{(char)c}:new char[]{highSurrogate(c),lowSurrogate(c)}; }
    public static int toChars(int c,char[] to,int at) { char[] chars=toChars(c); System.arraycopy(chars,0,to,at,chars.length); return chars.length; }
    public static int digit(char c,int radix) { return digit((int)c,radix); }
    public static int digit(int c,int radix) {
        if(radix<2 || radix>36)return -1;
        int d=c>='a'&&c<='z'?c-'a'+10:c>='A'&&c<='Z'?c-'A'+10:c>=0xff41&&c<=0xff5a?c-0xff41+10:c>=0xff21&&c<=0xff3a?c-0xff21+10:-1;
        if(d<0)for(int zero:jbv.runtime.Unicode.DIGIT_ZEROS)if(c>=zero&&c<zero+10){d=c-zero;break;}
        return d<radix?d:-1;
    }
    public static char forDigit(int digit,int radix) { return radix<2||radix>36||digit<0||digit>=radix?0:(char)(digit<10?'0'+digit:'a'+digit-10); }
    public static boolean isDigit(char c) { return isDigit((int)c); }
    public static boolean isDigit(int c) { return digit(c,10)>=0; }
    public static boolean isWhitespace(char c) { return isWhitespace((int)c); }
    public static boolean isWhitespace(int c) { return (c>=9&&c<=13)||(c>=28&&c<=32)||c==0x1680||(c>=0x2000&&c<=0x2006)||(c>=0x2008&&c<=0x200a)||c==0x2028||c==0x2029||c==0x205f||c==0x3000; }
    public static char reverseBytes(char c) { return (char)((c<<8)|(c>>>8)); }
}
