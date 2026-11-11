package java.lang;
public final class Math {
    public static final double E=2.7182818284590452354, PI=3.14159265358979323846;
    private Math() {}
    public static int abs(int x) { return x<0?-x:x; }
    public static long abs(long x) { return x<0?-x:x; }
    public static float abs(float x) { return Float.intBitsToFloat(Float.floatToRawIntBits(x)&0x7fffffff); }
    public static double abs(double x) { return Double.longBitsToDouble(Double.doubleToRawLongBits(x)&0x7fffffffffffffffL); }
    public static int absExact(int x) { if(x==Integer.MIN_VALUE)throw new ArithmeticException(); return abs(x); }
    public static long absExact(long x) { if(x==Long.MIN_VALUE)throw new ArithmeticException(); return abs(x); }
    public static int min(int a,int b) { return a<b?a:b; }
    public static long min(long a,long b) { return a<b?a:b; }
    public static int max(int a,int b) { return a>b?a:b; }
    public static long max(long a,long b) { return a>b?a:b; }
    public static float min(float a,float b) { if(Float.isNaN(a))return a; if(Float.isNaN(b))return b; if(a==0&&b==0)return Float.intBitsToFloat(Float.floatToRawIntBits(a)|Float.floatToRawIntBits(b)); return a<b?a:b; }
    public static double min(double a,double b) { if(Double.isNaN(a))return a; if(Double.isNaN(b))return b; if(a==0&&b==0)return Double.longBitsToDouble(Double.doubleToRawLongBits(a)|Double.doubleToRawLongBits(b)); return a<b?a:b; }
    public static float max(float a,float b) { if(Float.isNaN(a))return a; if(Float.isNaN(b))return b; if(a==0&&b==0)return Float.intBitsToFloat(Float.floatToRawIntBits(a)&Float.floatToRawIntBits(b)); return a>b?a:b; }
    public static double max(double a,double b) { if(Double.isNaN(a))return a; if(Double.isNaN(b))return b; if(a==0&&b==0)return Double.longBitsToDouble(Double.doubleToRawLongBits(a)&Double.doubleToRawLongBits(b)); return a>b?a:b; }
    public static double sqrt(double x) { return jbv.runtime.Support.sqrt(x); }
    public static double floor(double x) { return jbv.runtime.Support.roundIntegral(x,0); }
    public static double ceil(double x) { return jbv.runtime.Support.roundIntegral(x,1); }
    public static double rint(double x) { return jbv.runtime.Support.roundIntegral(x,2); }
    public static int round(float x) {
        int bits=Float.floatToRawIntBits(x), shift=149-((bits>>>23)&255);
        if(shift>=0&&shift<32) { int sig=(bits&0x7fffff)|0x800000; if(bits<0)sig=-sig; return ((sig>>shift)+1)>>1; }
        return (int)x;
    }
    public static long round(double x) {
        long bits=Double.doubleToRawLongBits(x); int shift=1074-(int)((bits>>>52)&2047);
        if(shift>=0&&shift<64) { long sig=(bits&0xfffffffffffffL)|0x10000000000000L; if(bits<0)sig=-sig; return ((sig>>shift)+1)>>1; }
        return (long)x;
    }
    public static float signum(float x) { return x==0||Float.isNaN(x)?x:x<0?-1:1; }
    public static double signum(double x) { return x==0||Double.isNaN(x)?x:x<0?-1:1; }
    public static float copySign(float magnitude,float sign) { return Float.intBitsToFloat((Float.floatToRawIntBits(magnitude)&0x7fffffff)|(Float.floatToRawIntBits(sign)&0x80000000)); }
    public static double copySign(double magnitude,double sign) { return Double.longBitsToDouble((Double.doubleToRawLongBits(magnitude)&0x7fffffffffffffffL)|(Double.doubleToRawLongBits(sign)&0x8000000000000000L)); }
    public static int getExponent(float x) { return ((Float.floatToRawIntBits(x)>>>23)&255)-127; }
    public static int getExponent(double x) { return (int)((Double.doubleToRawLongBits(x)>>>52)&2047)-1023; }
    public static float nextUp(float x) { if(Float.isNaN(x)||x==Float.POSITIVE_INFINITY)return x; if(x==0)return Float.MIN_VALUE; int b=Float.floatToRawIntBits(x); return Float.intBitsToFloat(b+(x>0?1:-1)); }
    public static double nextUp(double x) { if(Double.isNaN(x)||x==Double.POSITIVE_INFINITY)return x; if(x==0)return Double.MIN_VALUE; long b=Double.doubleToRawLongBits(x); return Double.longBitsToDouble(b+(x>0?1:-1)); }
    public static float nextDown(float x) { return -nextUp(-x); }
    public static double nextDown(double x) { return -nextUp(-x); }
    public static float nextAfter(float x,double direction) { if(Float.isNaN(x)||Double.isNaN(direction))return (float)(x+direction); return direction==x?(float)direction:direction>x?nextUp(x):nextDown(x); }
    public static double nextAfter(double x,double direction) { if(Double.isNaN(x)||Double.isNaN(direction))return x+direction; return direction==x?direction:direction>x?nextUp(x):nextDown(x); }
    public static float ulp(float x) { int e=getExponent(x); if(e==128)return abs(x); if(e==-127)return Float.MIN_VALUE; e-=23; return e>=-126?Float.intBitsToFloat((e+127)<<23):Float.intBitsToFloat(1<<(e+149)); }
    public static double ulp(double x) { int e=getExponent(x); if(e==1024)return abs(x); if(e==-1023)return Double.MIN_VALUE; e-=52; return e>=-1022?Double.longBitsToDouble((long)(e+1023)<<52):Double.longBitsToDouble(1L<<(e+1074)); }
    public static double scalb(double x,int n) { n=max(-2099,min(2099,n)); int r=n%512; x*=Double.longBitsToDouble((long)(r+1023)<<52); n-=r; while(n>0){x*=0x1p512;n-=512;} while(n<0){x*=0x1p-512;n+=512;} return x; }
    public static float scalb(float x,int n) { n=max(-278,min(278,n)); return (float)((double)x*Double.longBitsToDouble((long)(n+1023)<<52)); }
    public static double toDegrees(double x) { return x*(180.0/PI); }
    public static double toRadians(double x) { return x*(PI/180.0); }
    public static int addExact(int a,int b) { int r=a+b; if(((a^r)&(b^r))<0)throw new ArithmeticException(); return r; }
    public static long addExact(long a,long b) { long r=a+b; if(((a^r)&(b^r))<0)throw new ArithmeticException(); return r; }
    public static int subtractExact(int a,int b) { int r=a-b; if(((a^b)&(a^r))<0)throw new ArithmeticException(); return r; }
    public static long subtractExact(long a,long b) { long r=a-b; if(((a^b)&(a^r))<0)throw new ArithmeticException(); return r; }
    public static int multiplyExact(int a,int b) { return toIntExact((long)a*b); }
    public static long multiplyExact(long a,int b) { return multiplyExact(a,(long)b); }
    public static long multiplyExact(long a,long b) { long r=a*b; if((b!=0&&r/b!=a)||(a==Long.MIN_VALUE&&b==-1))throw new ArithmeticException(); return r; }
    public static long multiplyFull(int a,int b) { return (long)a*b; }
    public static int toIntExact(long x) { if((int)x!=x)throw new ArithmeticException(); return (int)x; }
    public static int negateExact(int x) { if(x==Integer.MIN_VALUE)throw new ArithmeticException(); return -x; }
    public static long negateExact(long x) { if(x==Long.MIN_VALUE)throw new ArithmeticException(); return -x; }
    public static int incrementExact(int x) { return addExact(x,1); }
    public static long incrementExact(long x) { return addExact(x,1); }
    public static int decrementExact(int x) { return subtractExact(x,1); }
    public static long decrementExact(long x) { return subtractExact(x,1); }
    public static int floorDiv(int a,int b) { int q=a/b; return ((a^b)<0&&a%b!=0)?q-1:q; }
    public static long floorDiv(long a,long b) { long q=a/b; return ((a^b)<0&&a%b!=0)?q-1:q; }
    public static long floorDiv(long a,int b) { return floorDiv(a,(long)b); }
    public static int floorMod(int a,int b) { return a-floorDiv(a,b)*b; }
    public static long floorMod(long a,long b) { return a-floorDiv(a,b)*b; }
    public static int floorMod(long a,int b) { return (int)floorMod(a,(long)b); }
    public static int ceilDiv(int a,int b) { int q=a/b; return ((a^b)>=0&&a%b!=0)?q+1:q; }
    public static long ceilDiv(long a,long b) { long q=a/b; return ((a^b)>=0&&a%b!=0)?q+1:q; }
    public static long ceilDiv(long a,int b) { return ceilDiv(a,(long)b); }
    public static int ceilMod(int a,int b) { return a-ceilDiv(a,b)*b; }
    public static long ceilMod(long a,long b) { return a-ceilDiv(a,b)*b; }
    public static int ceilMod(long a,int b) { return (int)ceilMod(a,(long)b); }
    public static int floorDivExact(int a,int b) { if(a==Integer.MIN_VALUE&&b==-1)throw new ArithmeticException(); return floorDiv(a,b); }
    public static long floorDivExact(long a,long b) { if(a==Long.MIN_VALUE&&b==-1)throw new ArithmeticException(); return floorDiv(a,b); }
    public static int ceilDivExact(int a,int b) { if(a==Integer.MIN_VALUE&&b==-1)throw new ArithmeticException(); return ceilDiv(a,b); }
    public static long ceilDivExact(long a,long b) { if(a==Long.MIN_VALUE&&b==-1)throw new ArithmeticException(); return ceilDiv(a,b); }
}
