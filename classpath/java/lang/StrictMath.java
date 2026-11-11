/*
 * ====================================================
 * Copyright (C) 1993, 2004 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 *
 * Java port of fdlibm 5.3 (netlib) for JByteVM: e_pow, e_log, e_exp, e_log10,
 * e_atan2, e_asin, e_acos, e_rem_pio2, k_rem_pio2, k_sin, k_cos, k_tan, s_sin,
 * s_cos, s_tan, s_atan, s_log1p, s_expm1, s_cbrt, e_hypot, e_sinh, e_cosh, s_tanh.
 */
package java.lang;

public final class StrictMath {
    private StrictMath() {}

    public static final double E=2.7182818284590452354, PI=3.14159265358979323846;
    private static final double DEGREES_TO_RADIANS=0.017453292519943295, RADIANS_TO_DEGREES=57.29577951308232;

    private static final double
        HUGE=1.0e300, TINY=1.0e-300, TWO24=1.67772160000000000000e+07, TWON24=5.96046447753906250000e-08,
        TWO53=9007199254740992.0, TWO54=1.80143985094819840000e+16, TWOM1000=9.33263618503218878990e-302,
        LN2_HI=6.93147180369123816490e-01, LN2_LO=1.90821492927058770002e-10, INVLN2=1.44269504088896338700e+00,
        O_THRESHOLD=7.09782712893383973096e+02, U_THRESHOLD=-7.45133219101941108420e+02,
        PIO2_HI=1.57079632679489655800e+00, PIO2_LO=6.12323399573676603587e-17, PIO4_HI=7.85398163397448278999e-01,
        PI_LO=1.2246467991473531772E-16, PIO4_LO=3.06161699786838301793e-17,
        // exp / pow polynomial
        P1=1.66666666666666019037e-01, P2=-2.77777777770155933842e-03, P3=6.61375632143793436117e-05,
        P4=-1.65339022054652515390e-06, P5=4.13813679705723846039e-08,
        // log / log1p polynomial
        Lg1=6.666666666666735130e-01, Lg2=3.999999999940941908e-01, Lg3=2.857142874366239149e-01,
        Lg4=2.222219843214978396e-01, Lg5=1.818357216161805012e-01, Lg6=1.531383769920937332e-01,
        Lg7=1.479819860511658591e-01,
        // asin / acos rational approximation
        pS0=1.66666666666666657415e-01, pS1=-3.25565818622400915405e-01, pS2=2.01212532134862925881e-01,
        pS3=-4.00555345006794114027e-02, pS4=7.91534994289814532176e-04, pS5=3.47933107596021167570e-05,
        qS1=-2.40339491173441421878e+00, qS2=2.02094576023350569471e+00, qS3=-6.88283971605453293030e-01,
        qS4=7.70381505559019352791e-02;

    // ---- word access (fdlibm __HI/__LO) ----
    private static int __HI(double x) { return (int)(Double.doubleToRawLongBits(x)>>>32); }
    private static int __LO(double x) { return (int)Double.doubleToRawLongBits(x); }
    private static double fromWords(int hi,int lo) { return Double.longBitsToDouble(((long)hi<<32)|(lo&0xffffffffL)); }
    private static double setHI(double x,int hi) { return fromWords(hi,__LO(x)); }
    private static double clearLO(double x) { return Double.longBitsToDouble(Double.doubleToRawLongBits(x)&0xffffffff00000000L); }
    /** x*2^n with a single rounding; valid for -1222 <= n <= 1023. */
    private static double scalbn(double x,int n) {
        if(n<-1022) return x*fromWords((n+200+1023)<<20,0)*0x1p-200;
        return x*fromWords((n+1023)<<20,0);
    }

    // ---- trivial delegations ----
    public static double sqrt(double a) { return Math.sqrt(a); }
    public static int abs(int a) { return Math.abs(a); }
    public static long abs(long a) { return Math.abs(a); }
    public static float abs(float a) { return Math.abs(a); }
    public static double abs(double a) { return Math.abs(a); }
    public static double toRadians(double angdeg) { return angdeg*DEGREES_TO_RADIANS; }
    public static double toDegrees(double angrad) { return angrad*RADIANS_TO_DEGREES; }

    // ---- trigonometric functions (s_sin, s_cos, s_tan, e_rem_pio2, k_*) ----
    public static double sin(double x) { return trig(x,0); }
    public static double cos(double x) { return trig(x,1); }
    public static double tan(double x) { return trig(x,2); }

    /** f: 0=sin, 1=cos, 2=tan. */
    private static double trig(double x,int f) {
        int ix=__HI(x)&0x7fffffff;
        if(ix<=0x3fe921fb) {           /* |x| ~< pi/4 */
            if(f==2) return kernelTan(x,0,1);
            return f==0?kernelSin(x,0,0):kernelCos(x,0);
        }
        if(ix>=0x7ff00000) return x-x; /* Inf or NaN */
        double[] y=new double[2];
        int n=remPio2(x,y);
        if(f==2) return kernelTan(y[0],y[1],1-((n&1)<<1));
        switch((n+f)&3) {              /* cos(x) = sin(x+pi/2) */
            case 0: return kernelSin(y[0],y[1],1);
            case 1: return kernelCos(y[0],y[1]);
            case 2: return -kernelSin(y[0],y[1],1);
            default: return -kernelCos(y[0],y[1]);
        }
    }

    private static double kernelSin(double x,double y,int iy) {
        if((__HI(x)&0x7fffffff)<0x3e400000) return x;  /* |x| < 2**-27 */
        double z=x*x, v=z*x;
        double r=8.33333333332248946124e-03+z*(-1.98412698298579493134e-04+z*(2.75573137070700676789e-06
                +z*(-2.50507602534068634195e-08+z*1.58969099521155010221e-10)));
        final double S1=-1.66666666666666324348e-01;
        if(iy==0) return x+v*(S1+z*r);
        return x-((z*(0.5*y-v*r)-y)-v*S1);
    }

    private static double kernelCos(double x,double y) {
        int ix=__HI(x)&0x7fffffff;
        if(ix<0x3e400000) return 1.0;  /* |x| < 2**-27 */
        double z=x*x;
        double r=z*(4.16666666666666019037e-02+z*(-1.38888888888741095749e-03+z*(2.48015872894767294178e-05
                +z*(-2.75573143513906633035e-07+z*(2.08757232129817482790e-09+z*-1.13596475577881948265e-11)))));
        if(ix<0x3FD33333) return 1.0-(0.5*z-(z*r-x*y));  /* |x| < 0.3 */
        double qx=ix>0x3fe90000?0.28125:fromWords(ix-0x00200000,0);
        return (1.0-qx)-((0.5*z-qx)-(z*r-x*y));
    }

    private static double kernelTan(double x,double y,int iy) {
        int hx=__HI(x), ix=hx&0x7fffffff;
        if(ix<0x3e300000) {            /* |x| < 2**-28 */
            if(((ix|__LO(x))|(iy+1))==0) return 1.0/Math.abs(x);
            if(iy==1) return x;
            return negInv(x+y,x,y);
        }
        boolean big=ix>=0x3FE59428;    /* |x| >= 0.6744 */
        if(big) {
            if(hx<0) { x=-x; y=-y; }
            x=(PIO4_HI-x)+(PIO4_LO-y);
            y=0.0;
        }
        double z=x*x, w=z*z;
        double r=1.33333333333201242699e-01+w*(2.18694882948595424599e-02+w*(3.59207910759131235356e-03
                +w*(5.88041240820264096874e-04+w*(7.81794442939557092300e-05+w*-1.85586374855275456654e-05))));
        double v=z*(5.39682539762260521377e-02+w*(8.86323982359930005737e-03+w*(1.45620945432529025516e-03
                +w*(2.46463134818469906812e-04+w*(7.14072491382608190305e-05+w*2.59073051863633712884e-05)))));
        double s=z*x;
        r=y+z*(s*(r+v)+y);
        r+=3.33333333333334091986e-01*s;
        w=x+r;
        if(big) {
            v=iy;
            return (1-((hx>>30)&2))*(v-2.0*(x-(w*w/(w+v)-r)));
        }
        return iy==1?w:negInv(w,x,r);
    }

    /** -1/w accurately, where w = x+r. */
    private static double negInv(double w,double x,double r) {
        double z=clearLO(w);
        double v=r-(z-x);
        double a=-1.0/w, t=clearLO(a);
        double s=1.0+t*z;
        return t+a*(s+t*v);
    }

    private static final int[] TWO_OVER_PI={
        0xA2F983,0x6E4E44,0x1529FC,0x2757D1,0xF534DD,0xC0DB62,0x95993C,0x439041,0xFE5163,0xABDEBB,0xC561B7,0x246E3A,
        0x424DD2,0xE00649,0x2EEA09,0xD1921C,0xFE1DEB,0x1CB129,0xA73EE8,0x8235F5,0x2EBB44,0x84E99C,0x7026B4,0x5F7E41,
        0x3991D6,0x398353,0x39F49C,0x845F8B,0xBDF928,0x3B1FF8,0x97FFDE,0x05980F,0xEF2F11,0x8B5A0A,0x6D1F6D,0x367ECF,
        0x27CB09,0xB74F46,0x3F669E,0x5FEA2D,0x7527BA,0xC7EBE5,0xF17B3D,0x0739F7,0x8A5292,0xEA6BFB,0x5FB11F,0x8D5D08,
        0x560330,0x46FC7B,0x6BABF0,0xCFBC20,0x9AF436,0x1DA9E3,0x91615E,0xE61B08,0x659985,0x5F14A0,0x68408D,0xFFD880,
        0x4D7327,0x310606,0x1556CA,0x73A8C9,0x60E27B,0xC08C6B};
    private static final int[] NPIO2_HW={
        0x3FF921FB,0x400921FB,0x4012D97C,0x401921FB,0x401F6A7A,0x4022D97C,0x4025FDBB,0x402921FB,
        0x402C463A,0x402F6A7A,0x4031475C,0x4032D97C,0x40346B9C,0x4035FDBB,0x40378FDB,0x403921FB,
        0x403AB41B,0x403C463A,0x403DD85A,0x403F6A7A,0x40407E4C,0x4041475C,0x4042106C,0x4042D97C,
        0x4043A28C,0x40446B9C,0x404534AC,0x4045FDBB,0x4046C6CB,0x40478FDB,0x404858EB,0x404921FB};
    private static final double[] PIO2={
        1.57079625129699707031e+00,7.54978941586159635335e-08,5.39030252995776476554e-15,3.28200341580791294123e-22,
        1.27065575308067607349e-29,1.22933308981111328932e-36,2.73370053816464559624e-44,2.16741683877804819444e-51};

    /** __ieee754_rem_pio2 for finite |x| > pi/4; the reduction is done on |x| and negated afterwards. */
    private static int remPio2(double x,double[] y) {
        final double PIO2_1=1.57079632673412561417e+00, PIO2_1T=6.07710050650619224932e-11,
            PIO2_2=6.07710050630396597660e-11, PIO2_2T=2.02226624879595063154e-21,
            PIO2_3=2.02226624871116645580e-21, PIO2_3T=8.47842766036889956997e-32;
        int hx=__HI(x), ix=hx&0x7fffffff, n;
        double ax=Math.abs(x), y0, y1;
        if(ix<0x4002d97c) {            /* |x| < 3pi/4, n=+-1 */
            double z=ax-PIO2_1;
            if(ix!=0x3ff921fb) { y0=z-PIO2_1T; y1=(z-y0)-PIO2_1T; }
            else { z-=PIO2_2; y0=z-PIO2_2T; y1=(z-y0)-PIO2_2T; }
            n=1;
        } else if(ix<=0x413921fb) {    /* |x| ~<= 2^19*(pi/2), medium size */
            n=(int)(ax*6.36619772367581382433e-01+0.5);
            double fn=n, r=ax-fn*PIO2_1, w=fn*PIO2_1T;
            y0=r-w;
            if(n>=32||ix==NPIO2_HW[n-1]) {
                int j=ix>>20;
                if(j-((__HI(y0)>>20)&0x7ff)>16) {   /* 2nd iteration, good to 118 bits */
                    double t=r;
                    w=fn*PIO2_2; r=t-w; w=fn*PIO2_2T-((t-r)-w); y0=r-w;
                    if(j-((__HI(y0)>>20)&0x7ff)>49) {   /* 3rd iteration, 151 bits */
                        t=r;
                        w=fn*PIO2_3; r=t-w; w=fn*PIO2_3T-((t-r)-w); y0=r-w;
                    }
                }
            }
            y1=(r-y0)-w;
        } else {                       /* large arguments */
            int e0=(ix>>20)-1046;      /* e0 = ilogb(z)-23 */
            double z=fromWords(ix-(e0<<20),__LO(x));
            double[] tx=new double[3];
            for(int i=0;i<2;i++) { tx[i]=(int)z; z=(z-tx[i])*TWO24; }
            tx[2]=z;
            int nx=3;
            while(tx[nx-1]==0.0) nx--;
            n=kernelRemPio2(tx,y,e0,nx);
            y0=y[0]; y1=y[1];
        }
        if(hx<0) { y0=-y0; y1=-y1; n=-n; }
        y[0]=y0; y[1]=y1;
        return n;
    }

    /** __kernel_rem_pio2 specialised for prec=2 (jk=jp=4) and ipio2=TWO_OVER_PI. */
    private static int kernelRemPio2(double[] x,double[] y,int e0,int nx) {
        final int jk=4;
        int[] iq=new int[20];
        double[] f=new double[20], fq=new double[20], q=new double[20];
        int jx=nx-1;
        int jv=(e0-3)/24; if(jv<0) jv=0;
        int q0=e0-24*(jv+1);
        for(int i=0,j=jv-jx;i<=jx+jk;i++,j++) f[i]=j<0?0.0:TWO_OVER_PI[j];
        for(int i=0;i<=jk;i++) q[i]=convolve(x,f,jx,i);
        int jz=jk, n, ih, i, j;
        double z, fw;
        while(true) {
            /* distill q[] into iq[] reversingly */
            for(i=0,j=jz,z=q[jz];j>0;i++,j--) {
                fw=(int)(TWON24*z);
                iq[i]=(int)(z-TWO24*fw);
                z=q[j-1]+fw;
            }
            z=scalbn(z,q0);
            z-=8.0*Math.floor(z*0.125);
            n=(int)z;
            z-=n;
            ih=0;
            if(q0>0) {
                i=iq[jz-1]>>(24-q0); n+=i;
                iq[jz-1]-=i<<(24-q0);
                ih=iq[jz-1]>>(23-q0);
            } else if(q0==0) ih=iq[jz-1]>>23;
            else if(z>=0.5) ih=2;
            if(ih>0) {                 /* q > 0.5 */
                n+=1;
                int carry=0;
                for(i=0;i<jz;i++) {    /* compute 1-q */
                    j=iq[i];
                    if(carry==0) { if(j!=0) { carry=1; iq[i]=0x1000000-j; } }
                    else iq[i]=0xffffff-j;
                }
                if(q0>0) iq[jz-1]&=0xffffff>>q0;   /* q0 is 1 or 2 */
                if(ih==2) {
                    z=1.0-z;
                    if(carry!=0) z-=scalbn(1.0,q0);
                }
            }
            if(z==0.0) {               /* check if recomputation is needed */
                j=0;
                for(i=jz-1;i>=jk;i--) j|=iq[i];
                if(j==0) {
                    int k=1;
                    while(iq[jk-k]==0) k++;
                    for(i=jz+1;i<=jz+k;i++) {
                        f[jx+i]=TWO_OVER_PI[jv+i];
                        q[i]=convolve(x,f,jx,i);
                    }
                    jz+=k;
                    continue;
                }
            }
            break;
        }
        if(z==0.0) {                   /* chop off zero terms */
            jz-=1; q0-=24;
            while(iq[jz]==0) { jz--; q0-=24; }
        } else {                       /* break z into 24-bit if necessary */
            z=scalbn(z,-q0);
            if(z>=TWO24) {
                fw=(int)(TWON24*z);
                iq[jz]=(int)(z-TWO24*fw);
                jz+=1; q0+=24;
                iq[jz]=(int)fw;
            } else iq[jz]=(int)z;
        }
        fw=scalbn(1.0,q0);
        for(i=jz;i>=0;i--) { q[i]=fw*iq[i]; fw*=TWON24; }
        for(i=jz;i>=0;i--) {
            fw=0.0;
            for(int k=0;k<=jk&&k<=jz-i;k++) fw+=PIO2[k]*q[i+k];
            fq[jz-i]=fw;
        }
        fw=0.0;
        for(i=jz;i>=0;i--) fw+=fq[i];
        y[0]=ih==0?fw:-fw;
        fw=fq[0]-fw;
        for(i=1;i<=jz;i++) fw+=fq[i];
        y[1]=ih==0?fw:-fw;
        return n&7;
    }

    private static double convolve(double[] x,double[] f,int jx,int i) {
        double fw=0.0;
        for(int j=0;j<=jx;j++) fw+=x[j]*f[jx+i-j];
        return fw;
    }

    // ---- inverse trigonometric functions (e_asin, e_acos, s_atan, e_atan2) ----
    /** R(t) = p(t)/q(t) shared by asin and acos. */
    private static double asinR(double t) {
        double p=t*(pS0+t*(pS1+t*(pS2+t*(pS3+t*(pS4+t*pS5)))));
        double q=1.0+t*(qS1+t*(qS2+t*(qS3+t*qS4)));
        return p/q;
    }

    public static double asin(double x) {
        int hx=__HI(x), ix=hx&0x7fffffff;
        double t;
        if(ix>=0x3ff00000) {           /* |x| >= 1 */
            if(((ix-0x3ff00000)|__LO(x))==0) return x*PIO2_HI+x*PIO2_LO;
            return (x-x)/(x-x);
        }
        if(ix<0x3fe00000) {            /* |x| < 0.5 */
            if(ix<0x3e400000) return x;
            return x+x*asinR(x*x);
        }
        double w=1.0-Math.abs(x);
        t=w*0.5;
        double r=asinR(t), s=Math.sqrt(t);
        if(ix>=0x3FEF3333) {           /* |x| > 0.975 */
            t=PIO2_HI-(2.0*(s+s*r)-PIO2_LO);
        } else {
            w=clearLO(s);
            double c=(t-w*w)/(s+w);
            double p=2.0*s*r-(PIO2_LO-2.0*c);
            double q=PIO4_HI-2.0*w;
            t=PIO4_HI-(p-q);
        }
        return hx>0?t:-t;
    }

    public static double acos(double x) {
        final double PI_=3.14159265358979311600e+00;
        int hx=__HI(x), ix=hx&0x7fffffff;
        if(ix>=0x3ff00000) {           /* |x| >= 1 */
            if(((ix-0x3ff00000)|__LO(x))==0) return hx>0?0.0:PI_+2.0*PIO2_LO;
            return (x-x)/(x-x);
        }
        if(ix<0x3fe00000) {            /* |x| < 0.5 */
            if(ix<=0x3c600000) return PIO2_HI+PIO2_LO;
            return PIO2_HI-(x-(PIO2_LO-x*asinR(x*x)));
        }
        if(hx<0) {                     /* x < -0.5 */
            double z=(1.0+x)*0.5, s=Math.sqrt(z);
            double w=asinR(z)*s-PIO2_LO;
            return PI_-2.0*(s+w);
        }
        double z=(1.0-x)*0.5, s=Math.sqrt(z), df=clearLO(s);
        double c=(z-df*df)/(s+df);
        double w=asinR(z)*s+c;
        return 2.0*(df+w);
    }

    private static final double[] ATANHI={4.63647609000806093515e-01,7.85398163397448278999e-01,
        9.82793723247329054082e-01,1.57079632679489655800e+00};
    private static final double[] ATANLO={2.26987774529616870924e-17,3.06161699786838301793e-17,
        1.39033110312309984516e-17,6.12323399573676603587e-17};

    public static double atan(double x) {
        int hx=__HI(x), ix=hx&0x7fffffff, id;
        if(ix>=0x44100000) {           /* |x| >= 2^66 */
            if(ix>0x7ff00000||(ix==0x7ff00000&&__LO(x)!=0)) return x+x;
            return hx>0?ATANHI[3]+ATANLO[3]:-ATANHI[3]-ATANLO[3];
        }
        if(ix<0x3fdc0000) {            /* |x| < 0.4375 */
            if(ix<0x3e200000) return x;
            id=-1;
        } else {
            x=Math.abs(x);
            if(ix<0x3ff30000) {        /* |x| < 1.1875 */
                if(ix<0x3fe60000) { id=0; x=(2.0*x-1.0)/(2.0+x); }
                else { id=1; x=(x-1.0)/(x+1.0); }
            } else if(ix<0x40038000) { id=2; x=(x-1.5)/(1.0+1.5*x); }
            else { id=3; x=-1.0/x; }
        }
        double z=x*x, w=z*z;
        double s1=z*(3.33333333333329318027e-01+w*(1.42857142725034663711e-01+w*(9.09088713343650656196e-02
                +w*(6.66107313738753120669e-02+w*(4.97687799461593236017e-02+w*1.62858201153657823623e-02)))));
        double s2=w*(-1.99999999998764832476e-01+w*(-1.11111104054623557880e-01+w*(-7.69187620504482999495e-02
                +w*(-5.83357013379057348645e-02+w*-3.65315727442169155270e-02))));
        if(id<0) return x-x*(s1+s2);
        z=ATANHI[id]-((x*(s1+s2)-ATANLO[id])-x);
        return hx<0?-z:z;
    }

    public static double atan2(double y,double x) {
        final double PI_=3.1415926535897931160E+00, PI_O_2=1.5707963267948965580E+00, PI_O_4=7.8539816339744827900E-01;
        int hx=__HI(x), ix=hx&0x7fffffff, lx=__LO(x);
        int hy=__HI(y), iy=hy&0x7fffffff, ly=__LO(y);
        if((ix|((lx|-lx)>>>31))>0x7ff00000||(iy|((ly|-ly)>>>31))>0x7ff00000) return x+y;  /* NaN */
        if(((hx-0x3ff00000)|lx)==0) return atan(y);   /* x=1.0 */
        int m=((hy>>31)&1)|((hx>>30)&2);              /* 2*sign(x)+sign(y) */
        double z;
        if((iy|ly)==0) {               /* y = 0 */
            if(m<2) return y;
            z=PI_+TINY;
        } else if((ix|lx)==0) {        /* x = 0 */
            return hy<0?-PI_O_2-TINY:PI_O_2+TINY;
        } else if(ix==0x7ff00000) {    /* x is INF */
            if(iy==0x7ff00000) z=m<2?PI_O_4+TINY:3.0*PI_O_4+TINY;
            else z=m<2?0.0:PI_+TINY;
        } else if(iy==0x7ff00000) {    /* y is INF */
            return hy<0?-PI_O_2-TINY:PI_O_2+TINY;
        } else {
            int k=(iy-ix)>>20;
            if(k>60) z=PI_O_2+0.5*PI_LO;
            else if(hx<0&&k<-60) z=0.0;
            else z=atan(Math.abs(y/x));
            switch(m) {
                case 0: return z;
                case 1: return -z;
                case 2: return PI_-(z-PI_LO);
                default: return (z-PI_LO)-PI_;
            }
        }
        return (m&1)==0?z:-z;
    }

    // ---- exponential and logarithmic functions (e_exp, s_expm1, e_log, e_log10, s_log1p, e_pow) ----
    /** x - x^2*(P1+x^2*(P2+...)) shared by exp and pow. */
    private static double expC(double x) {
        double t=x*x;
        return x-t*(P1+t*(P2+t*(P3+t*(P4+t*P5))));
    }

    public static double exp(double x) {
        int hx=__HI(x), xsb=hx>>>31;
        hx&=0x7fffffff;
        if(hx>=0x40862E42) {           /* |x| >= 709.78... */
            if(hx>=0x7ff00000) {
                if(((hx&0xfffff)|__LO(x))!=0) return x+x;  /* NaN */
                return xsb==0?x:0.0;
            }
            if(x>O_THRESHOLD) return HUGE*HUGE;
            if(x<U_THRESHOLD) return TWOM1000*TWOM1000;
        }
        double hi=0.0, lo=0.0;
        int k=0;
        if(hx>0x3fd62e42) {            /* |x| > 0.5 ln2 */
            if(hx<0x3FF0A2B2) {        /* and |x| < 1.5 ln2 */
                if(xsb==0) { hi=x-LN2_HI; lo=LN2_LO; k=1; }
                else { hi=x+LN2_HI; lo=-LN2_LO; k=-1; }
            } else {
                k=(int)(INVLN2*x+(xsb==0?0.5:-0.5));
                double t=k;
                hi=x-t*LN2_HI;
                lo=t*LN2_LO;
            }
            x=hi-lo;
        } else if(hx<0x3e300000) return 1.0+x;   /* |x| < 2**-28 */
        double c=expC(x);
        if(k==0) return 1.0-((x*c)/(c-2.0)-x);
        double y=1.0-((lo-(x*c)/(2.0-c))-hi);
        if(k>=-1021) return setHI(y,__HI(y)+(k<<20));
        return setHI(y,__HI(y)+((k+1000)<<20))*TWOM1000;
    }

    public static double expm1(double x) {
        final double Q1=-3.33333333333331316428e-02, Q2=1.58730158725481460165e-03, Q3=-7.93650757867487942473e-05,
            Q4=4.00821782732936239552e-06, Q5=-2.01099218183624371326e-07;
        int hx=__HI(x);
        boolean neg=hx<0;
        hx&=0x7fffffff;
        if(hx>=0x4043687A) {           /* |x| >= 56*ln2 */
            if(hx>=0x40862E42) {       /* |x| >= 709.78... */
                if(hx>=0x7ff00000) {
                    if(((hx&0xfffff)|__LO(x))!=0) return x+x;  /* NaN */
                    return neg?-1.0:x;
                }
                if(x>O_THRESHOLD) return HUGE*HUGE;
            }
            if(neg) return TINY-1.0;   /* x < -56*ln2 */
        }
        double hi, lo, c=0.0, t, y;
        int k;
        if(hx>0x3fd62e42) {            /* |x| > 0.5 ln2 */
            if(hx<0x3FF0A2B2) {        /* and |x| < 1.5 ln2 */
                if(!neg) { hi=x-LN2_HI; lo=LN2_LO; k=1; }
                else { hi=x+LN2_HI; lo=-LN2_LO; k=-1; }
            } else {
                k=(int)(INVLN2*x+(neg?-0.5:0.5));
                t=k;
                hi=x-t*LN2_HI;
                lo=t*LN2_LO;
            }
            x=hi-lo;
            c=(hi-x)-lo;
        } else if(hx<0x3c900000) return x;   /* |x| < 2**-54 */
        else k=0;
        double hfx=0.5*x, hxs=x*hfx;
        double r1=1.0+hxs*(Q1+hxs*(Q2+hxs*(Q3+hxs*(Q4+hxs*Q5))));
        t=3.0-r1*hfx;
        double e=hxs*((r1-t)/(6.0-x*t));
        if(k==0) return x-(x*e-hxs);
        e=(x*(e-c)-c);
        e-=hxs;
        if(k==-1) return 0.5*(x-e)-0.5;
        if(k==1) return x<-0.25?-2.0*(e-(x+0.5)):1.0+2.0*(x-e);
        if(k<=-2||k>56) {
            y=1.0-(e-x);
            return setHI(y,__HI(y)+(k<<20))-1.0;
        }
        if(k<20) {
            t=fromWords(0x3ff00000-(0x200000>>k),0);   /* 1-2^-k */
            y=t-(e-x);
        } else {
            t=fromWords((0x3ff-k)<<20,0);              /* 2^-k */
            y=x-(e+t);
            y+=1.0;
        }
        return setHI(y,__HI(y)+(k<<20));
    }

    public static double log(double x) {
        int hx=__HI(x), lx=__LO(x), k=0;
        if(hx<0x00100000) {            /* x < 2**-1022 */
            if(((hx&0x7fffffff)|lx)==0) return -TWO54/0.0;   /* log(+-0) = -inf */
            if(hx<0) return (x-x)/0.0;                      /* log(-#) = NaN */
            k-=54; x*=TWO54;
            hx=__HI(x);
        }
        if(hx>=0x7ff00000) return x+x;
        k+=(hx>>20)-1023;
        hx&=0x000fffff;
        int i=(hx+0x95f64)&0x100000;
        x=setHI(x,hx|(i^0x3ff00000));  /* normalize x or x/2 */
        k+=(i>>20);
        double f=x-1.0, dk=k;
        if((0x000fffff&(2+hx))<3) {    /* |f| < 2**-20 */
            if(f==0.0) return k==0?0.0:dk*LN2_HI+dk*LN2_LO;
            double R=f*f*(0.5-0.33333333333333333*f);
            return k==0?f-R:dk*LN2_HI-((R-dk*LN2_LO)-f);
        }
        double s=f/(2.0+f), z=s*s, w=z*z;
        i=hx-0x6147a;
        int j=0x6b851-hx;
        double t1=w*(Lg2+w*(Lg4+w*Lg6));
        double t2=z*(Lg1+w*(Lg3+w*(Lg5+w*Lg7)));
        i|=j;
        double R=t2+t1;
        if(i>0) {
            double hfsq=0.5*f*f;
            return k==0?f-(hfsq-s*(hfsq+R)):dk*LN2_HI-((hfsq-(s*(hfsq+R)+dk*LN2_LO))-f);
        }
        return k==0?f-s*(f-R):dk*LN2_HI-((s*(f-R)-dk*LN2_LO)-f);
    }

    public static double log10(double x) {
        int hx=__HI(x), lx=__LO(x), k=0;
        if(hx<0x00100000) {            /* x < 2**-1022 */
            if(((hx&0x7fffffff)|lx)==0) return -TWO54/0.0;
            if(hx<0) return (x-x)/0.0;
            k-=54; x*=TWO54;
            hx=__HI(x);
        }
        if(hx>=0x7ff00000) return x+x;
        k+=(hx>>20)-1023;
        int i=k>>>31;
        hx=(hx&0x000fffff)|((0x3ff-i)<<20);
        double y=k+i;
        x=setHI(x,hx);
        double z=y*3.69423907715893078616e-13+4.34294481903251816668e-01*log(x);
        return z+y*3.01029995663611771306e-01;
    }

    public static double log1p(double x) {
        int hx=__HI(x), ax=hx&0x7fffffff, k=1, hu=0;
        double f=0.0, c=0.0;
        if(hx<0x3FDA827A) {            /* x < 0.41422 */
            if(ax>=0x3ff00000) {       /* x <= -1.0 */
                if(x==-1.0) return -TWO54/0.0;
                return Double.NaN;             /* log1p(x<-1): HotSpot returns the canonical NaN */
            }
            if(ax<0x3e200000) {        /* |x| < 2**-29 */
                if(ax<0x3c900000) return x;   /* |x| < 2**-54 */
                return x-x*x*0.5;
            }
            if(hx>0||hx<=0xbfd2bec3) { k=0; f=x; hu=1; }   /* -0.2929<x<0.41422 */
        }
        if(hx>=0x7ff00000) return x+x;
        if(k!=0) {
            double u;
            if(hx<0x43400000) {
                u=1.0+x;
                hu=__HI(u);
                k=(hu>>20)-1023;
                c=(k>0)?1.0-(u-x):x-(u-1.0);   /* correction term */
                c/=u;
            } else {
                u=x;
                hu=__HI(u);
                k=(hu>>20)-1023;
                c=0;
            }
            hu&=0x000fffff;
            if(hu<0x6a09e) u=setHI(u,hu|0x3ff00000);   /* normalize u */
            else {
                k+=1;
                u=setHI(u,hu|0x3fe00000);              /* normalize u/2 */
                hu=(0x00100000-hu)>>2;
            }
            f=u-1.0;
        }
        double hfsq=0.5*f*f, R;
        if(hu==0) {                    /* |f| < 2**-20 */
            if(f==0.0) {
                if(k==0) return 0.0;
                c+=k*LN2_LO;
                return k*LN2_HI+c;
            }
            R=hfsq*(1.0-0.66666666666666666*f);
            return k==0?f-R:k*LN2_HI-((R-(k*LN2_LO+c))-f);
        }
        double s=f/(2.0+f), z=s*s;
        R=z*(Lg1+z*(Lg2+z*(Lg3+z*(Lg4+z*(Lg5+z*(Lg6+z*Lg7))))));
        return k==0?f-(hfsq-s*(hfsq+R)):k*LN2_HI-((hfsq-(s*(hfsq+R)+(k*LN2_LO+c)))-f);
    }

    public static double pow(double x,double y) {
        final double DP_H=5.84962487220764160156e-01, DP_L=1.35003920212974897128e-08,
            L1=5.99999999999994648725e-01, L2=4.28571428578550184252e-01, L3=3.33333329818377432918e-01,
            L4=2.72728123808534006489e-01, L5=2.30660745775561754067e-01, L6=2.06975017800338417784e-01,
            LG2=6.93147180559945286227e-01, LG2_H=6.93147182464599609375e-01, LG2_L=-1.90465429995776804525e-09,
            OVT=8.0085662595372944372e-17, CP=9.61796693925975554329e-01, CP_H=9.61796700954437255859e-01,
            CP_L=-7.02846165095275826516e-09, IVLN2=1.44269504088896338700e+00, IVLN2_H=1.44269502162933349609e+00,
            IVLN2_L=1.92596299112661746887e-08;
        double z, ax, p_h, p_l, t1, t2, r, s, t, u, v, w;
        int i, j, k, n;
        int hx=__HI(x), lx=__LO(x), hy=__HI(y), ly=__LO(y);
        int ix=hx&0x7fffffff, iy=hy&0x7fffffff;

        if((iy|ly)==0) return 1.0;    /* y==0: x**0 = 1 */
        if(ix>0x7ff00000||((ix==0x7ff00000)&&(lx!=0))||iy>0x7ff00000||((iy==0x7ff00000)&&(ly!=0)))
            return x+y;                /* NaN */

        /* yisint = 0: y not an integer, 1: odd integer, 2: even integer (only computed for x < 0) */
        int yisint=0;
        if(hx<0) {
            if(iy>=0x43400000) yisint=2;
            else if(iy>=0x3ff00000) {
                k=(iy>>20)-0x3ff;
                if(k>20) {
                    j=ly>>>(52-k);
                    if((j<<(52-k))==ly) yisint=2-(j&1);
                } else if(ly==0) {
                    j=iy>>(20-k);
                    if((j<<(20-k))==iy) yisint=2-(j&1);
                }
            }
        }

        if(ly==0) {                    /* special value of y */
            if(iy==0x7ff00000) {       /* y is +-inf */
                if(((ix-0x3ff00000)|lx)==0) return y-y;    /* (+-1)**+-inf is NaN */
                if(ix>=0x3ff00000) return hy>=0?y:0.0;     /* (|x|>1)**+-inf = inf,0 */
                return hy<0?-y:0.0;                        /* (|x|<1)**-,+inf = inf,0 */
            }
            if(iy==0x3ff00000) return hy<0?1.0/x:x;       /* y is +-1 */
            if(hy==0x40000000) return x*x;                 /* y is 2 */
            if(hy==0x3fe00000&&hx>=0) return Math.sqrt(x);/* y is 0.5, x >= +0 */
        }

        ax=Math.abs(x);
        if(lx==0&&(ix==0x7ff00000||ix==0||ix==0x3ff00000)) {   /* x is +-0,+-inf,+-1 */
            z=ax;
            if(hy<0) z=1.0/z;
            if(hx<0) {
                if(((ix-0x3ff00000)|yisint)==0) z=(z-z)/(z-z);  /* (-1)**non-int is NaN */
                else if(yisint==1) z=-z;
            }
            return z;
        }

        n=(hx>>31)+1;
        if((n|yisint)==0) return (x-x)/(x-x);   /* (x<0)**(non-int) is NaN */
        s=1.0;
        if((n|(yisint-1))==0) s=-1.0;           /* (-ve)**(odd int) */

        if(iy>0x41e00000) {            /* |y| > 2**31 */
            if(iy>0x43f00000) {        /* |y| > 2**64, must o/uflow */
                if(ix<=0x3fefffff) return hy<0?HUGE*HUGE:TINY*TINY;
                if(ix>=0x3ff00000) return hy>0?HUGE*HUGE:TINY*TINY;
            }
            if(ix<0x3fefffff) return hy<0?s*HUGE*HUGE:s*TINY*TINY;
            if(ix>0x3ff00000) return hy>0?s*HUGE*HUGE:s*TINY*TINY;
            /* |1-x| <= 2**-20: log(x) by x-x^2/2+x^3/3-x^4/4 */
            t=ax-1.0;
            w=(t*t)*(0.5-t*(0.3333333333333333333333-t*0.25));
            u=IVLN2_H*t;
            v=t*IVLN2_L-w*IVLN2;
            t1=clearLO(u+v);
            t2=v-(t1-u);
        } else {
            n=0;
            if(ix<0x00100000) { ax*=TWO53; n-=53; ix=__HI(ax); }   /* subnormal x */
            n+=((ix)>>20)-0x3ff;
            j=ix&0x000fffff;
            ix=j|0x3ff00000;           /* normalize ix */
            if(j<=0x3988E) k=0;        /* |x| < sqrt(3/2) */
            else if(j<0xBB67A) k=1;    /* |x| < sqrt(3) */
            else { k=0; n+=1; ix-=0x00100000; }
            ax=setHI(ax,ix);
            double bp=k==0?1.0:1.5, dp_h=k==0?0.0:DP_H, dp_l=k==0?0.0:DP_L;

            /* ss = s_h+s_l = (x-1)/(x+1) or (x-1.5)/(x+1.5) */
            u=ax-bp;
            v=1.0/(ax+bp);
            double ss=u*v, s_h=clearLO(ss);
            double t_h=fromWords(((ix>>1)|0x20000000)+0x00080000+(k<<18),0);
            double t_l=ax-(t_h-bp);
            double s_l=v*((u-s_h*t_h)-s_h*t_l);
            /* log(ax) */
            double s2=ss*ss;
            r=s2*s2*(L1+s2*(L2+s2*(L3+s2*(L4+s2*(L5+s2*L6)))));
            r+=s_l*(s_h+ss);
            s2=s_h*s_h;
            t_h=clearLO(3.0+s2+r);
            t_l=r-((t_h-3.0)-s2);
            u=s_h*t_h;
            v=s_l*t_h+t_l*ss;
            p_h=clearLO(u+v);
            p_l=v-(p_h-u);
            double z_h=CP_H*p_h;
            double z_l=CP_L*p_h+p_l*CP+dp_l;
            /* log2(ax) = n + dp_h + z_h + z_l */
            t=n;
            t1=clearLO(((z_h+z_l)+dp_h)+t);
            t2=z_l-(((t1-t)-dp_h)-z_h);
        }

        /* (y1+y2)*(t1+t2) */
        double y1=clearLO(y);
        p_l=(y-y1)*t1+y*t2;
        p_h=y1*t1;
        z=p_l+p_h;
        j=__HI(z);
        i=__LO(z);
        if(j>=0x40900000) {            /* z >= 1024 */
            if(((j-0x40900000)|i)!=0) return s*HUGE*HUGE;
            if(p_l+OVT>z-p_h) return s*HUGE*HUGE;
        } else if((j&0x7fffffff)>=0x4090cc00) {   /* z <= -1075 */
            if(((j-0xc090cc00)|i)!=0) return s*TINY*TINY;
            if(p_l<=z-p_h) return s*TINY*TINY;
        }

        /* 2**(p_h+p_l) */
        i=j&0x7fffffff;
        k=(i>>20)-0x3ff;
        n=0;
        if(i>0x3fe00000) {             /* |z| > 0.5: n = [z+0.5] */
            n=j+(0x00100000>>(k+1));
            k=((n&0x7fffffff)>>20)-0x3ff;
            t=fromWords(n&~(0x000fffff>>k),0);
            n=((n&0x000fffff)|0x00100000)>>(20-k);
            if(j<0) n=-n;
            p_h-=t;
        }
        t=clearLO(p_l+p_h);
        u=t*LG2_H;
        v=(p_l-(t-p_h))*LG2+t*LG2_L;
        z=u+v;
        w=v-(z-u);
        t1=expC(z);
        r=(z*t1)/(t1-2.0)-(w+z*w);
        z=1.0-(r-z);
        j=__HI(z)+(n<<20);
        z=(j>>20)<=0?scalbn(z,n):setHI(z,j);   /* subnormal output */
        return s*z;
    }

    // ---- cube root and hypot (s_cbrt, e_hypot) ----
    public static double cbrt(double x) {
        final int B1=715094163, B2=696219795;
        final double C=5.42857142857142815906e-01, D=-7.05306122448979611050e-01, E_=1.41428571428571436819e+00,
            F=1.60714285714285720630e+00, G=3.57142857142857150787e-01;
        int hx=__HI(x), sign=hx&0x80000000;
        hx^=sign;
        if(hx>=0x7ff00000) return x;             /* cbrt(NaN,INF) is itself (HotSpot keeps even a signalling NaN) */
        if((hx|__LO(x))==0) return x;            /* cbrt(0) is itself */
        x=setHI(x,hx);                           /* x <- |x| */
        double t;
        if(hx<0x00100000) {                      /* subnormal */
            t=fromWords(0x43500000,0)*x;         /* 2**54 * x */
            t=setHI(t,__HI(t)/3+B2);
        } else t=fromWords(hx/3+B1,0);
        /* new cbrt to 23 bits */
        double r=t*t/x, s=C+r*t;
        t*=G+F/(s+E_+D/s);
        /* chop to 20 bits and make it larger than cbrt(x) */
        t=fromWords(__HI(t)+1,0);
        /* one step newton iteration to 53 bits */
        s=t*t;
        r=x/s;
        double w=t+t;
        r=(r-t)/(w+r);
        t=t+t*r;
        return setHI(t,__HI(t)|sign);
    }

    public static double hypot(double x,double y) {
        double a, b, t1, t2, w;
        int j, k, ha=__HI(x)&0x7fffffff, hb=__HI(y)&0x7fffffff;
        if(hb>ha) { a=y; b=x; j=ha; ha=hb; hb=j; } else { a=x; b=y; }
        a=setHI(a,ha);                 /* a <- |a| */
        b=setHI(b,hb);                 /* b <- |b| */
        if((ha-hb)>0x3c00000) return a+b;   /* x/y > 2**60 */
        k=0;
        if(ha>0x5f300000) {            /* a > 2**500 */
            if(ha>=0x7ff00000) {       /* Inf or NaN */
                w=a+b;
                if(((ha&0xfffff)|__LO(a))==0) w=a;
                if(((hb^0x7ff00000)|__LO(b))==0) w=b;
                return w;
            }
            ha-=0x25800000; hb-=0x25800000; k+=600;   /* scale by 2**-600 */
            a=setHI(a,ha);
            b=setHI(b,hb);
        }
        if(hb<0x20b00000) {            /* b < 2**-500 */
            if(hb<=0x000fffff) {       /* subnormal b or 0 */
                if((hb|__LO(b))==0) return a;
                t1=fromWords(0x7fd00000,0);   /* 2^1022 */
                b*=t1;
                a*=t1;
                k-=1022;
            } else {                   /* scale by 2^600 */
                ha+=0x25800000;
                hb+=0x25800000;
                k-=600;
                a=setHI(a,ha);
                b=setHI(b,hb);
            }
        }
        w=a-b;
        if(w>b) {
            t1=fromWords(ha,0);
            t2=a-t1;
            w=Math.sqrt(t1*t1-(b*(-b)-t2*(a+t1)));
        } else {
            a=a+a;
            double y1=fromWords(hb,0), y2=b-y1;
            t1=fromWords(ha+0x00100000,0);
            t2=a-t1;
            w=Math.sqrt(t1*y1-(w*(-w)-(t1*y2+t2*b)));
        }
        return k!=0?fromWords(0x3ff00000+(k<<20),0)*w:w;
    }

    // ---- hyperbolic functions (e_sinh, e_cosh, s_tanh) ----
    public static double sinh(double x) {
        int jx=__HI(x), ix=jx&0x7fffffff;
        if(ix>=0x7ff00000) return x+x; /* INF or NaN */
        double h=jx<0?-0.5:0.5, t;
        if(ix<0x40360000) {            /* |x| < 22 */
            if(ix<0x3e300000) return x;   /* |x| < 2**-28 */
            t=expm1(Math.abs(x));
            if(ix<0x3ff00000) return h*(2.0*t-t*t/(t+1.0));
            return h*(t+t/(t+1.0));
        }
        if(ix<0x40862E42) return h*exp(Math.abs(x));   /* |x| in [22, log(maxdouble)] */
        if(Math.abs(x)<=fromWords(0x408633CE,0x8fb9f87d)) {   /* |x| <= overflow threshold */
            double w=exp(0.5*Math.abs(x));
            t=h*w;
            return t*w;
        }
        return x*1.0e307;              /* overflow */
    }

    public static double cosh(double x) {
        int ix=__HI(x)&0x7fffffff;
        if(ix>=0x7ff00000) return x*x; /* INF or NaN */
        double t;
        if(ix<0x3fd62e43) {            /* |x| in [0,0.5*ln2] */
            t=expm1(Math.abs(x));
            double w=1.0+t;
            if(ix<0x3c800000) return w;   /* cosh(tiny) = 1 */
            return 1.0+(t*t)/(w+w);
        }
        if(ix<0x40360000) {            /* |x| in [0.5*ln2,22] */
            t=exp(Math.abs(x));
            return 0.5*t+0.5/t;
        }
        if(ix<0x40862E42) return 0.5*exp(Math.abs(x));   /* |x| in [22, log(maxdouble)] */
        if(Math.abs(x)<=fromWords(0x408633CE,0x8fb9f87d)) {
            double w=exp(0.5*Math.abs(x));
            t=0.5*w;
            return t*w;
        }
        return HUGE*HUGE;              /* overflow */
    }

    public static double tanh(double x) {
        int jx=__HI(x), ix=jx&0x7fffffff;
        double t, z;
        if(ix>=0x7ff00000) return jx>=0?1.0/x+1.0:1.0/x-1.0;   /* +-inf -> +-1, NaN */
        if(ix<0x40360000) {            /* |x| < 22 */
            if(ix<0x3c800000) return x*(1.0+x);   /* |x| < 2**-55 */
            if(ix>=0x3ff00000) {       /* |x| >= 1 */
                t=expm1(2.0*Math.abs(x));
                z=1.0-2.0/(t+2.0);
            } else {
                t=expm1(-2.0*Math.abs(x));
                z=-t/(t+2.0);
            }
        } else z=1.0-TINY;             /* |x| >= 22: +-1 */
        return jx>=0?z:-z;
    }
}
