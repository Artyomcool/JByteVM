package jbv.runtime;
import java.util.*;

/** java.util.Formatter conversions (US/ROOT symbols) for String.format, String.formatted and PrintStream.printf. */
public final class Format {
    private static final int LEFT=1, UPPER=2, ALT=4, PLUS=8, SPACE=16, ZERO=32, GROUP=64, PAREN=128, PREV=256;
    private static final String FLAGS="-^#+ 0,(<";
    // Shortest decimal f*10^e with n digits (JDK FormattedFPDecimal), used by %e %f %g.
    private long f;
    private int e, n;

    private Format(double v) {
        String s=Double.toString(v);
        int k=s.indexOf('E');
        if(k>=0) { e=Integer.parseInt(s.substring(k+1)); s=s.substring(0,k); }
        for(int i=0;i<s.length();i++) { char c=s.charAt(i); if(c=='.')e-=s.length()-1-i; else f=f*10+c-'0'; }
        while(f!=0&&f%10==0) { f/=10; e++; }
        if(f==0)e=0;
        for(long x=f;x!=0;x/=10)n++;
    }
    private static long pow10(int k) { long p=1; while(k-->0)p*=10; return p; }
    private void round(long pp) {
        if(n==0||pp<0) { f=0; e=0; n=1; return; }
        if(pp>=n)return;
        int p=(int)pp;
        e+=n-p;
        long pow=pow10(n-p);
        f=(f+(pow>>1))/pow;
        if(p==0) { n=1; if(f==0)e=0; return; }
        n=p;
        if(f==pow10(p)) { f/=10; e++; }
    }
    private String plain() {
        String d=Long.toString(f);
        return e>=0?d+"0".repeat(e):n+e>0?d.substring(0,n+e)+"."+d.substring(n+e):"0."+"0".repeat(-e-n)+d;
    }
    private String scientific(int prec) {
        String d=Long.toString(f);
        return prec==0?d.substring(0,1):d.charAt(0)+"."+d.substring(1);
    }
    private String exponent() {
        int er=n+e-1, a=Math.abs(er);
        return (er<0?"-":"+")+(a<10?"0":"")+a;
    }

    public static String format(String format, Object... args) {
        // Parse everything first, as java.util.Formatter does, so syntax errors win over argument errors.
        int[] specs=new int[56];
        int count=0, i=0, max=format.length();
        while(i<max) {
            if(count+14>specs.length)specs=Arrays.copyOf(specs,specs.length*2);
            int at=format.indexOf('%',i);
            if(at<0)at=max;
            if(i!=at) { specs[count]=i; specs[count+1]=at; specs[count+2]=-2; specs[count+6]=0; count+=7; }
            if(at==max)break;
            i=at+1;
            if(i>=max)throw new UnknownFormatConversionException("%");
            char c=format.charAt(i);
            int off=valid(c)?spec(specs,count,format,i,i,0,0,0,(char)0,c):parse(specs,count,format,i,max,c);
            if(off==0)throw new UnknownFormatConversionException(String.valueOf(c));
            i+=off; count+=7;
        }
        StringBuilder out=new StringBuilder();
        int last=-1, lasto=-1;
        for(int s=0;s<count;s+=7) {
            int idx=specs[s+2], fl=specs[s+3], w=specs[s+4], p=specs[s+5];
            int cv=specs[s+6];
            char c=(char)cv;
            Object arg=null;
            if(idx!=-2) {
                if(idx==0)last=++lasto; else if(idx>0)last=idx-1;
                if(last<0||args!=null&&last>args.length-1)throw new MissingFormatArgumentException(spec(idx,fl,w,p,cv));
                if(args!=null)arg=args[last];
            }
            if(c==0)out.append(format,specs[s],specs[s+1]);
            else if(c=='n')out.append(System.lineSeparator());
            else if(cv>0xffff) {
                if(arg!=null&&!(arg instanceof Long))fail(c,arg);
                if(arg!=null)throw new UnsupportedOperationException("date/time conversions are not supported");
                justify(out,(fl&UPPER)!=0?"NULL":"null",fl,w);
            }
            else print(out,arg,c,fl,w,p);
        }
        return out.toString();
    }
    private static boolean valid(char c) { return "bBhHsScCdoxXeEgGfaAn%".indexOf(c)>=0; }
    private static boolean digit(char c) { return c>='0'&&c<='9'; }
    private static boolean conversion(char c) { return (c|32)>='a'&&(c|32)<='z'||c=='%'; }
    /** Port of Formatter.FormatSpecifierParser; returns the consumed length or 0. */
    private static int parse(int[] specs, int at, String s, int start, int max, char first) {
        int off=start, argSize=0, j;
        char c=first;
        for(j=off;j<max&&digit(c=s.charAt(j));j++) {}
        if(j==off||c!='$')c=first;
        else { j++; if(j<max)c=s.charAt(j); argSize=j-off; off=j; }
        for(j=off;j<max&&FLAGS.indexOf(c=s.charAt(j))>=0&&c!='^';j++) {}
        int flagSize=j-off;
        for(off=j;j<max&&digit(c=s.charAt(j));j++) {}
        int widthSize=j-off, precSize=0;
        off=j;
        if(c=='.') {
            for(j=++off;j<max&&digit(c=s.charAt(j));j++) {}
            if(j==off)return 0;
            precSize=j-off+1; off=j;
        }
        char t=0, conv=0;
        if((c=='t'||c=='T')&&off+1<max) { char c1=s.charAt(off+1); if(conversion(c1)) { t=c; conv=c1; off+=2; } }
        else if(conversion(c)) { conv=c; off++; }
        else return 0;
        if(argSize+flagSize+widthSize+precSize+t+conv==0)return 0;
        spec(specs,at,s,start,start+argSize,flagSize,widthSize,precSize,t,conv);
        return off-start;
    }
    /** Port of the FormatSpecifier constructor: stores and validates one specifier. */
    private static int spec(int[] specs, int at, String s, int start, int argEnd, int flagSize, int widthSize, int precSize, char t, char c) {
        int idx=0, fl=0, w=-1, p=-1, flagEnd=argEnd+flagSize, widthEnd=flagEnd+widthSize;
        if(argEnd>start&&(idx=number(s,start,argEnd-1))<=0)throw new IllegalFormatArgumentIndexException(idx);
        for(int i=argEnd;i<flagEnd;i++) {
            int v=1<<FLAGS.indexOf(s.charAt(i));
            if((fl&v)!=0)throw new DuplicateFormatFlagsException(flags(v));
            fl|=v;
        }
        if((fl&PREV)!=0)idx=-1;
        if(widthSize>0&&(w=number(s,flagEnd,widthEnd))<0)throw new IllegalFormatWidthException(w);
        if(precSize>0&&(p=number(s,widthEnd+1,widthEnd+precSize))<0)throw new IllegalFormatPrecisionException(p);
        if(t!=0) {
            // Date/time: the JDK's parse-time checks; printing a date is unsupported.
            if(t=='T')fl|=UPPER;
            if(p!=-1)throw new IllegalFormatPrecisionException(p);
            if("HIklMNLQpsSTzZaAbBCdehjmyYrRcDF".indexOf(c)<0)throw new UnknownFormatConversionException("t"+c);
            bad(fl,ALT|PLUS|SPACE|ZERO|GROUP|PAREN,c);
            if(w==-1&&(fl&LEFT)!=0)throw new MissingFormatWidthException(spec(idx,fl,w,p,c|0x10000));
            specs[at+2]=idx; specs[at+3]=fl; specs[at+4]=w; specs[at+5]=p; specs[at+6]=c|0x10000;
            return 0;
        }
        if(!valid(c))throw new UnknownFormatConversionException(String.valueOf(c));
        if(c<'a'&&c!='%') { fl|=UPPER; c+=32; }
        if(c=='n'||c=='%')idx=-2;
        if("bsh".indexOf(c)>=0) {
            if(c!='s'&&(fl&ALT)!=0)throw new FormatFlagsConversionMismatchException(flags(ALT),c);
            if(w==-1&&(fl&LEFT)!=0)throw new MissingFormatWidthException(spec(idx,fl,w,p,c));
            bad(fl,PLUS|SPACE|ZERO|GROUP|PAREN,c);
        } else if(c=='c') {
            if(p!=-1)throw new IllegalFormatPrecisionException(p);
            bad(fl,ALT|PLUS|SPACE|ZERO|GROUP|PAREN,c);
            if(w==-1&&(fl&LEFT)!=0)throw new MissingFormatWidthException(spec(idx,fl,w,p,c));
        } else if(idx!=-2) {
            if(w==-1&&(fl&(LEFT|ZERO))!=0)throw new MissingFormatWidthException(spec(idx,fl,w,p,c));
            if((fl&(PLUS|SPACE))==(PLUS|SPACE)||(fl&(LEFT|ZERO))==(LEFT|ZERO))throw new IllegalFormatFlagsException(flags(fl));
            if(c=='d'||c=='o'||c=='x') {
                if(p!=-1)throw new IllegalFormatPrecisionException(p);
                bad(fl,c=='d'?ALT:GROUP,c);
            } else bad(fl,c=='a'?PAREN|GROUP:c=='e'?GROUP:c=='g'?ALT:0,c);
        } else {
            if(p!=-1)throw new IllegalFormatPrecisionException(p);
            if(c=='%') {
                if(fl!=LEFT&&fl!=0)throw new IllegalFormatFlagsException(flags(fl));
                if(w==-1&&fl==LEFT)throw new MissingFormatWidthException(spec(idx,fl,w,p,c));
            } else {
                if(w!=-1)throw new IllegalFormatWidthException(w);
                if(fl!=0)throw new IllegalFormatFlagsException(flags(fl));
            }
        }
        specs[at+2]=idx; specs[at+3]=fl; specs[at+4]=w; specs[at+5]=p; specs[at+6]=c;
        return argEnd+flagSize+widthSize+precSize+1-start;
    }
    /** Decimal digits as int, or Integer.MIN_VALUE when not representable. */
    private static int number(String s, int from, int to) {
        long v=0;
        while(from<to)if((v=v*10+s.charAt(from++)-'0')>Integer.MAX_VALUE)return Integer.MIN_VALUE;
        return (int)v;
    }
    private static String flags(int fl) {
        StringBuilder sb=new StringBuilder();
        for(int i=0;i<9;i++)if((fl>>i&1)!=0)sb.append(FLAGS.charAt(i));
        return sb.toString();
    }
    private static String spec(int idx, int fl, int w, int p, int c) {
        StringBuilder sb=new StringBuilder("%").append(flags(fl&~UPPER));
        if(idx>0)sb.append(idx).append('$');
        if(w!=-1)sb.append(w);
        if(p!=-1)sb.append('.').append(p);
        if(c>0xffff)sb.append((fl&UPPER)!=0?'T':'t');
        return sb.append((char)((fl&UPPER)!=0&&c<0x10000?c-32:c)).toString();
    }
    private static void bad(int fl, int bad, char c) {
        if((fl&bad)!=0)throw new FormatFlagsConversionMismatchException(flags(fl&bad),c);
    }
    private static void print(StringBuilder out, Object arg, char c, int fl, int w, int p) {
        String s;
        if(c=='%')s="%";
        else if(c=='b')s=arg==null?"false":arg instanceof Boolean?arg.toString():"true";
        else if(c=='h')s=arg==null?"null":Integer.toHexString(arg.hashCode());
        else if(c=='s') {
            if((fl&ALT)!=0)throw new FormatFlagsConversionMismatchException(flags(ALT),'s');
            s=String.valueOf(arg);
        } else if(arg==null)s="null";
        else if(c=='c') {
            if(arg instanceof Character)s=arg.toString();
            else {
                int v=arg instanceof Byte?(Byte)arg:arg instanceof Short?(Short)arg:arg instanceof Integer?(Integer)arg:fail(c,arg);
                if(!Character.isValidCodePoint(v))throw new IllegalFormatCodePointException(v);
                s=new String(Character.toChars(v));
            }
        } else {
            StringBuilder sb=new StringBuilder();
            if(c=='d'||c=='o'||c=='x') {
                long v;
                int bits=arg instanceof Byte?8:arg instanceof Short?16:arg instanceof Integer?32:arg instanceof Long?64:fail(c,arg);
                v=((Number)arg).longValue();
                if(c=='d') {
                    boolean neg=v<0;
                    sign(sb,neg,fl);
                    magnitude(sb,Long.toString(v),neg?1:0,fl,adjust(w,fl,neg));
                    if(neg&&(fl&PAREN)!=0)sb.append(')');
                } else {
                    bad(fl,PAREN|SPACE|PLUS,c);
                    if(v<0&&bits<64)v+=1L<<bits;
                    String d=c=='o'?Long.toOctalString(v):Long.toHexString(v);
                    String pre=(fl&ALT)==0?"":c=='o'?"0":"0x";
                    sb.append(pre);
                    if((fl&ZERO)!=0)zeros(sb,w-d.length()-pre.length());
                    sb.append(d);
                }
            } else {
                double v=arg instanceof Float?(Float)arg:arg instanceof Double?(Double)arg:fail(c,arg);
                boolean neg=v<0||v==0&&1/v<0;
                if(v!=v)sb.append("NaN");
                else {
                    sign(sb,neg,fl);
                    if(Double.isInfinite(v))sb.append("Infinity"); else number(sb,Math.abs(v),c,fl,w,p,neg);
                    if(neg&&(fl&PAREN)!=0)sb.append(')');
                }
            }
            justify(out,(fl&UPPER)!=0?sb.toString().toUpperCase():sb,fl,w);
            return;
        }
        if(p!=-1&&p<s.length())s=s.substring(0,p);
        justify(out,(fl&UPPER)!=0?s.toUpperCase():s,fl,w);
    }
    private static int fail(char c, Object arg) { throw new IllegalFormatConversionException(c,arg.getClass()); }
    private static void sign(StringBuilder sb, boolean neg, int fl) {
        if(neg)sb.append((fl&PAREN)!=0?'(':'-');
        else if((fl&PLUS)!=0)sb.append('+');
        else if((fl&SPACE)!=0)sb.append(' ');
    }
    private static int adjust(int w, int fl, boolean neg) { return w!=-1&&neg&&(fl&PAREN)!=0?w-1:w; }
    private static void zeros(StringBuilder sb, int n) { while(n-->0)sb.append('0'); }
    private static void justify(StringBuilder out, CharSequence s, int fl, int w) {
        boolean left=(fl&LEFT)!=0;
        if(left)out.append(s);
        for(int i=s.length();i<w;i++)out.append(' ');
        if(!left)out.append(s);
    }
    /** Port of Formatter.localizedMagnitude with '.' and ',' (groups of three). */
    private static void magnitude(StringBuilder sb, CharSequence v, int offset, int fl, int w) {
        int begin=sb.length(), len=v.length(), dot=len;
        for(int j=offset;j<len;j++)if(v.charAt(j)=='.') { dot=j; break; }
        boolean group=(fl&GROUP)!=0;
        for(int j=offset;j<len;j++) {
            sb.append(v.charAt(j));
            if(j==dot)group=false;
            else if(group&&j!=dot-1&&(dot-j)%3==1)sb.append(',');
        }
        if(w>sb.length()&&(fl&ZERO)!=0)sb.insert(begin,"0".repeat(w-sb.length()));
    }
    private static void addZeros(StringBuilder sb, int prec) {
        int i=0, len=sb.length();
        while(i<len&&sb.charAt(i)!='.')i++;
        if(i==len) { if(prec<=0)return; sb.append('.'); len++; }
        zeros(sb,prec-(len-i-1));
    }
    private static void number(StringBuilder sb, double v, char c, int fl, int w, int p, boolean neg) {
        if(c=='a') {
            int prec=p==-1?0:p==0?1:p;
            String s=hex(v,prec);
            sb.append("0x");
            if((fl&ZERO)!=0)zeros(sb,w-s.length()-((fl&(SPACE|PLUS))!=0||neg?3:2));
            int at=s.indexOf('p');
            StringBuilder m=new StringBuilder(s.substring(0,at));
            if(prec!=0)addZeros(m,prec);
            sb.append(m).append(s,at,s.length());
            return;
        }
        int prec=p==-1?6:p;
        Format d=new Format(v);
        String exp=null;
        StringBuilder m=new StringBuilder();
        if(c=='f') { d.round(d.n+d.e+(long)prec); m.append(d.plain()); }
        else if(c=='e') { d.round(prec+1L); m.append(d.scientific(prec)); exp=v==0?"+00":d.exponent(); }
        else {
            if(prec==0)prec=1;
            if(v==0) { m.append('0'); prec--; }
            else {
                d.round(prec);
                int er=d.n+d.e-1;
                if(-4<=er&&er<prec) { m.append(d.plain()); prec-=er+1; }
                else { m.append(d.scientific(--prec)); exp=d.exponent(); }
            }
        }
        addZeros(m,prec);
        if((fl&ALT)!=0&&prec==0)m.append('.');
        magnitude(sb,m,0,fl,adjust(exp==null||w==-1?w:w-exp.length()-1,fl,neg));
        if(exp!=null)sb.append('e').append(exp);
    }
    /** Formatter.hexDouble for a non-negative finite value: Double.toHexString without "0x", or rounded to prec hex digits. */
    private static String hex(double d, int prec) {
        long b=Double.doubleToRawLongBits(d), m=b&(1L<<52)-1;
        int x=(int)(b>>>52);
        if(d==0)return "0.0p0";
        if(prec==0||prec>=13)return (x==0?"0.":"1.")+strip(Long.toHexString(m|1L<<52).substring(1))+"p"+(x==0?-1022:x-1023);
        if(x==0) { int sh=Long.numberOfLeadingZeros(m)-11; m=m<<sh&(1L<<52)-1; x=1-sh; }
        int s=52-4*prec;
        long q=m>>>s, r=m&(1L<<s)-1, half=1L<<s-1;
        if(r>half||r==half&&(q&1)!=0)q++;
        if(q>>>4*prec!=0) { q=0; x++; }
        if(x>=2047)return "1.0p1024";
        return "1."+strip(Long.toHexString(q|1L<<4*prec).substring(1))+"p"+(x-1023);
    }
    private static String strip(String h) {
        int n=h.length();
        while(n>1&&h.charAt(n-1)=='0')n--;
        return h.substring(0,n);
    }
}
