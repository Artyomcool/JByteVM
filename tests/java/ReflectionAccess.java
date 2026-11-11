import java.lang.reflect.*;
import reflection.AccessTarget;
/* JByteVM has no access checks; this checks that opened members work as on HotSpot. */
public class ReflectionAccess extends AccessTarget {
    public static int check(int ignored)throws Exception {
        int n=0;AccessTarget base=new AccessTarget();ReflectionAccess child=new ReflectionAccess();
        Field f=AccessTarget.class.getDeclaredField("secret");f.setAccessible(true);
        if(f.getInt(base)==13)n|=1;
        if(f.trySetAccessible()&&f.canAccess(base))n|=2;
        f.setInt(base,5);if(f.getInt(base)==5)n|=4;
        Method m=AccessTarget.class.getDeclaredMethod("value");m.setAccessible(true);
        if(m.canAccess(base))n|=8;
        if((Integer)m.invoke(child)==17)n|=16;
        if((Integer)m.invoke(base)==17)n|=32;
        Method h=AccessTarget.hidden().getMethod("run");h.setAccessible(true);
        if(h.canAccess(null))n|=64;
        if((Integer)h.invoke(null)==1)n|=128;
        return n;
    }
}
