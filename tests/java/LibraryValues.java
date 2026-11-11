public class LibraryValues {
    static void check(boolean b) { if(!b)throw new AssertionError(); }
    public static int boxing() {
        Number[] a={Byte.valueOf((byte)-7),Short.valueOf((short)32760),Integer.valueOf(-129),Long.valueOf(0x123456789L),Float.valueOf(1.5f),Double.valueOf(-2.75)};
        int r=0; for(Number n:a)r=31*r+n.intValue()+n.byteValue()+n.shortValue();
        check(Integer.valueOf(127)==Integer.valueOf(127)); check(Long.valueOf(-128)==Long.valueOf(-128));
        check(Character.valueOf('A')==Character.valueOf('A')); check(Boolean.valueOf(true)==Boolean.TRUE);
        check(Float.valueOf(Float.NaN).equals(Float.valueOf(Float.intBitsToFloat(0x7fa00001))));
        check(!Double.valueOf(-0.0).equals(Double.valueOf(0.0)));
        check(Integer.TYPE==int.class && Double.TYPE==double.class && Void.TYPE==void.class);
        check(Boolean.parseBoolean("tRuE") && !Boolean.parseBoolean(null));
        return r;
    }
    public static int parseIntegers() {
        check(Integer.parseInt("-2147483648")==Integer.MIN_VALUE);
        check(Long.parseLong("9223372036854775807")==Long.MAX_VALUE);
        check(Long.parseUnsignedLong("18446744073709551615")==-1L);
        check(Integer.parseUnsignedInt("ffffffff",16)==-1);
        check(Integer.parseInt("\u0661\u0662\u0663")==123);
        check(Integer.decode("-0x80000000")==Integer.MIN_VALUE);
        check(Long.decode("-010")==-8L && Short.decode("#7fff")==32767);
        String[] bad={"2147483648","-2147483649","","+"," 1","1_0","++1","0x10"};
        int n=0; for(String s:bad)try{Integer.parseInt(s);}catch(NumberFormatException e){n++;}
        try{Byte.parseByte("128");}catch(NumberFormatException e){n++;}
        try{Short.parseShort("-32769");}catch(NumberFormatException e){n++;}
        try{Long.parseUnsignedLong("18446744073709551616");}catch(NumberFormatException e){n++;}
        try{Integer.parseUnsignedInt("-0");}catch(NumberFormatException e){n++;}
        return n;
    }
    public static long integerBits(long a,int n) {
        return Long.rotateLeft(a,n)^Long.reverse(a)^Long.reverseBytes(a)^Long.highestOneBit(a)^Long.lowestOneBit(a)
            ^Long.bitCount(a)^Long.numberOfLeadingZeros(a)^Long.numberOfTrailingZeros(a)
            ^Integer.rotateRight((int)a,n)^Integer.reverse((int)a)^Integer.reverseBytes((int)a)
            ^Integer.highestOneBit((int)a)^Integer.lowestOneBit((int)a)^Integer.numberOfLeadingZeros((int)a)^Integer.numberOfTrailingZeros((int)a);
    }
    public static int integerText(long a,int radix) {
        return Long.toString(a,radix).hashCode()^Long.toUnsignedString(a,radix).hashCode()
            ^Integer.toString((int)a,radix).hashCode()^Integer.toUnsignedString((int)a,radix).hashCode();
    }
    public static int arrays() {
        int n=0; int[] a={1,2,3,4,5}; System.arraycopy(a,0,a,1,4);
        for(int x:a)n=n*7+x; System.arraycopy(a,1,a,0,4); for(int x:a)n=n*7+x;
        Object[] from={"a","b",Integer.valueOf(2),"d"}; String[] to={"x","x","x","x"};
        try{System.arraycopy(from,0,to,0,4);}catch(ArrayStoreException e){check(to[0].equals("a")&&to[1].equals("b")&&to[2].equals("x"));n++;}
        try{System.arraycopy(null,-1,to,0,-1);}catch(NullPointerException e){n+=2;}
        try{System.arraycopy(new int[0],0,new long[0],0,0);}catch(ArrayStoreException e){n+=4;}
        try{System.arraycopy(a,-1,a,0,0);}catch(IndexOutOfBoundsException e){n+=8;}
        long[] b={Long.MIN_VALUE,123,Long.MAX_VALUE}; System.arraycopy(b,0,b,1,2); check(b[1]==Long.MIN_VALUE&&b[2]==123);
        char[] c={'a','\ud800','\u0000'};System.arraycopy(c,0,c,1,2);check(c[1]=='a'&&c[2]=='\ud800');
        check(System.identityHashCode(null)==0); return n;
    }
    public static int exactMath() {
        int n=0;
        try{Math.addExact(Integer.MAX_VALUE,1);}catch(ArithmeticException e){n++;}
        try{Math.multiplyExact(Long.MIN_VALUE,-1L);}catch(ArithmeticException e){n+=2;}
        try{Math.subtractExact(Long.MIN_VALUE,1);}catch(ArithmeticException e){n+=4;}
        try{Math.toIntExact(0x100000000L);}catch(ArithmeticException e){n+=8;}
        for(int a=-21;a<22;a++)for(int b=-5;b<6;b++)if(b!=0)n=31*n+Math.floorDiv(a,b)+Math.floorMod(a,b)+Math.ceilDiv(a,b)+Math.ceilMod(a,b);
        return n;
    }
    public static double floating(double a,int op) {
        return switch(op) {case 0->Math.sqrt(a);case 1->Math.floor(a);case 2->Math.ceil(a);case 3->Math.rint(a);
            case 4->Math.abs(a);case 5->Math.ulp(a);case 6->Math.nextUp(a);case 7->Math.nextDown(a);
            case 8->Math.signum(a);case 9->Math.min(a,-0.0);default->Math.max(a,0.0);};
    }
    public static double scale(double a,int n) {return Math.scalb(a,n);}
    public static float scale(float a,int n) {return Math.scalb(a,n);}
    public static long round(double a) {return Math.round(a);}
    public static int round(float a) {return Math.round(a);}
    public static long parseD(String s) {try{return Double.doubleToRawLongBits(Double.parseDouble(s));}catch(NumberFormatException e){return 0x12345678L;}}
    public static long parseF(String s) {try{return Float.floatToRawIntBits(Float.parseFloat(s))&0xffffffffL;}catch(NumberFormatException e){return 0x12345678L;}}
    static final Object lock=new Object();
    static synchronized int reentrant(int n) {if(n==0){LibraryValues.class.notify();return 1;}synchronized(LibraryValues.class){return reentrant(n-1)+1;}}
    static int inner() {synchronized(lock){lock.notifyAll();return 3;}}
    public static int monitors() {
        int n=reentrant(7);
        try{lock.notify();}catch(IllegalMonitorStateException e){n+=10;}
        synchronized(lock){n+=inner();System.gc();lock.notify();try{throw new IllegalArgumentException();}catch(IllegalArgumentException e){n++;}}
        try{synchronized(lock){throw new IllegalStateException();}}catch(IllegalStateException e){n++;}
        try{lock.notifyAll();}catch(IllegalMonitorStateException e){n+=100;}
        try{synchronized((Object)null){n++;}}catch(NullPointerException e){n+=1000;}
        return n;
    }
    public static synchronized int lockedBudget(int n) {while(n--!=0){}return n;}
    public static int checkUnlocked() {try{LibraryValues.class.notify();return 0;}catch(IllegalMonitorStateException e){return 1;}}
    public static long clocks() {return System.currentTimeMillis()^System.nanoTime();}
    public static int output() {System.out.print("hello");System.err.println(42);return 7;}
    public static int fpProbe(double one,double tiny) {
        int n=one+0x1p-53==one?1:0;
        if(one+0x1p-30!=one)n+=2;
        if(tiny*one==Double.MIN_VALUE)n+=4;
        return n;
    }
    public static native int fpNested();
    public static int fpChain() {int n=fpNested();return fpProbe(1.0,Double.MIN_VALUE)==7?n:0;}
}
