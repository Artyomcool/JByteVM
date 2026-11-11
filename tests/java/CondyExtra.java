import java.lang.invoke.*;
public class CondyExtra {
    static int calls;
    static boolean ready;
    public interface Carrier {static Object nil(){return new Object();}}
    private static Object nil(MethodHandles.Lookup lookup,String name,Class<?> type){if(lookup.lookupClass()!=Carrier.class||type!=Object.class)throw new AssertionError();calls++;return null;}
    private static long number(MethodHandles.Lookup lookup,String name,Class<?> type){if(!ready||lookup.lookupClass()!=CondyExtra.class||type!=long.class)throw new AssertionError();calls++;System.gc();return 12345678901L;}
    static long value(){return 0;}
    public static int lifecycle(int ignored){int start=calls;ready=true;int n=0;if(Carrier.nil()==null&&Carrier.nil()==null&&calls==start+1)n|=1;if(value()==12345678901L&&value()==12345678901L&&calls==start+2)n|=2;System.gc();if(Carrier.nil()==null&&value()==12345678901L&&calls==start+2)n|=4;return n;}
    public static native int nativeBootstrap(MethodHandles.Lookup lookup,String name,Class<?> type);
    static int nativeValue(){return 0;}
    public static int readNative(int ignored){return nativeValue();}
}
