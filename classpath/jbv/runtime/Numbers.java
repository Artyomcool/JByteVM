package jbv.runtime;
public final class Numbers {
    private Numbers() {}
    public static long unsignedDivide(long a,long b) {
        if (b < 0) return unsignedCompare(a,b) < 0 ? 0 : 1;
        if (a >= 0) return a/b;
        long q=((a>>>1)/b)<<1, r=a-q*b;
        return q+(unsignedCompare(r,b)>=0?1:0);
    }
    public static int unsignedCompare(long a,long b) {
        a ^= Long.MIN_VALUE; b ^= Long.MIN_VALUE;
        return a<b?-1:a==b?0:1;
    }
    /** The JDK's NumberFormatException.forInputString message. */
    static NumberFormatException bad(String text,int radix){return new NumberFormatException("For input string: \""+text+"\""+(radix==10?"":" under radix "+radix));}
    public static long parse(String text,int radix,int bits,boolean unsigned) {
        if (text==null) throw new NumberFormatException("Cannot parse null string: null");
        if (radix<2 || radix>36) throw new NumberFormatException("radix "+radix+(radix<2?" less than Character.MIN_RADIX":" greater than Character.MAX_RADIX"));
        if (text.isEmpty()) throw bad(text,radix);
        int i=0, length=text.length(); boolean negative=false;
        char first=text.charAt(0);
        if (first=='-' || first=='+') { negative=first=='-'; i++; }
        if (unsigned && negative) throw new NumberFormatException("Illegal leading minus sign on unsigned string "+text+".");
        if (i==length) throw bad(text,radix);
        long limit=bits==64?Long.MIN_VALUE:-(1L<<(bits-1));
        if (!unsigned) {
            if (!negative) limit++;
            long cutoff=limit/radix, value=0;
            for (;i<length;i++) {
                int digit=Character.digit(text.charAt(i),radix);
                if (digit<0 || value<cutoff) throw bad(text,radix);
                value*=radix;
                if (value<limit+digit) throw bad(text,radix);
                value-=digit;
            }
            return negative?value:-value;
        }
        long max=bits==64?-1L:(1L<<bits)-1;
        long cutoff=unsignedDivide(max,radix), remainder=max-cutoff*radix, value=0;
        for (;i<length;i++) {
            int digit=Character.digit(text.charAt(i),radix);
            int compare=unsignedCompare(value,cutoff);
            if (digit<0) throw bad(text,radix);
            if (compare>0 || (compare==0 && digit>remainder)) throw new NumberFormatException("String value "+text+" exceeds range of unsigned "+(bits==64?"long":"int")+".");
            value=value*radix+digit;
        }
        return value;
    }
    public static long decode(String text,int bits) {
        if (text==null || text.isEmpty()) throw new NumberFormatException();
        int i=0, radix=10; boolean negative=text.charAt(0)=='-';
        if (negative || text.charAt(0)=='+') i++;
        if (text.startsWith("0x",i) || text.startsWith("0X",i)) { radix=16; i+=2; }
        else if (text.startsWith("#",i)) { radix=16; i++; }
        else if (text.startsWith("0",i) && text.length()>i+1) { radix=8; i++; }
        if (i>=text.length() || text.charAt(i)=='-' || text.charAt(i)=='+') throw new NumberFormatException();
        return parse(negative?"-"+text.substring(i):text.substring(i),radix,bits,false);
    }
    public static String text(long value,int radix,boolean unsigned) {
        if (radix<2 || radix>36) radix=10;
        char[] chars=new char[65]; int at=chars.length;
        if (unsigned) {
            do { long q=unsignedDivide(value,radix); int d=(int)(value-q*radix); chars[--at]=(char)(d<10?'0'+d:'a'+d-10); value=q; } while(value!=0);
        } else {
            boolean negative=value<0; if (!negative) value=-value;
            do { int d=(int)-(value%radix); chars[--at]=(char)(d<10?'0'+d:'a'+d-10); value/=radix; } while(value!=0);
            if (negative) chars[--at]='-';
        }
        return new String(chars,at,chars.length-at);
    }
}
