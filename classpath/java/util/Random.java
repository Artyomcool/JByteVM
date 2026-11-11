package java.util;
/** java.util.Random: the specified 48-bit LCG, so seeded sequences match the JDK. */
public class Random implements java.io.Serializable {
    private static final long MULTIPLIER=0x5DEECE66DL,MASK=(1L<<48)-1;
    private static long uniquifier=8682522807148012L;
    private long seed;
    private double nextNextGaussian;
    private boolean haveNextNextGaussian;
    public Random(){this((uniquifier*=1181783497276652981L)^System.nanoTime());}
    public Random(long seed){setSeed(seed);}
    public synchronized void setSeed(long seed){this.seed=(seed^MULTIPLIER)&MASK;haveNextNextGaussian=false;}
    protected synchronized int next(int bits){seed=(seed*MULTIPLIER+0xBL)&MASK;return (int)(seed>>>(48-bits));}
    public void nextBytes(byte[] bytes){for(int i=0,n=bytes.length;i<n;)for(int r=nextInt(),k=Math.min(n-i,4);k-->0;r>>=8)bytes[i++]=(byte)r;}
    public int nextInt(){return next(32);}
    public int nextInt(int bound){
        if(bound<=0)throw new IllegalArgumentException("bound must be positive");
        int r=next(31),m=bound-1;
        if((bound&m)==0)return (int)((bound*(long)r)>>31);
        for(int u=r;u-(r=u%bound)+m<0;u=next(31)){}
        return r;
    }
    public int nextInt(int origin,int bound){
        if(origin>=bound)throw new IllegalArgumentException("bound must be greater than origin");
        int r=nextInt(),n=bound-origin,m=n-1;
        if((n&m)==0)return (r&m)+origin;
        if(n>0){for(int u=r>>>1;u+m-(r=u%n)<0;u=nextInt()>>>1){}return r+origin;}
        while(r<origin||r>=bound)r=nextInt();
        return r;
    }
    public long nextLong(){return ((long)next(32)<<32)+next(32);}
    public boolean nextBoolean(){return next(1)!=0;}
    public float nextFloat(){return next(24)/(float)(1<<24);}
    public double nextDouble(){return (((long)next(26)<<27)+next(27))*0x1.0p-53;}
    public synchronized double nextGaussian(){
        if(haveNextNextGaussian){haveNextNextGaussian=false;return nextNextGaussian;}
        double a,b,s;
        do{a=2*nextDouble()-1;b=2*nextDouble()-1;s=a*a+b*b;}while(s>=1||s==0);
        double k=StrictMath.sqrt(-2*StrictMath.log(s)/s);
        nextNextGaussian=b*k;haveNextNextGaussian=true;return a*k;
    }
}
