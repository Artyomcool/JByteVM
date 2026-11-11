import java.lang.reflect.*;
import reflection.AccessTarget;
public class ReflectionAccess extends AccessTarget {
    public static int check(int ignored)throws Exception {
        int n=0;AccessTarget base=new AccessTarget();ReflectionAccess child=new ReflectionAccess();
        Field f=AccessTarget.class.getDeclaredField("secret");if(!f.canAccess(base))n|=1;
        try{f.get(base);}catch(IllegalAccessException e){n|=2;}
        if(f.trySetAccessible()&&f.canAccess(base)&&f.getInt(base)==13)n|=4;
        Method m=AccessTarget.class.getDeclaredMethod("value");if(m.canAccess(child)&&!m.canAccess(base))n|=8;
        if((Integer)m.invoke(child)==17)n|=16;
        try{m.invoke(base);}catch(IllegalAccessException e){n|=32;}
        Method h=AccessTarget.hidden().getMethod("run");try{h.invoke(null);}catch(IllegalAccessException e){n|=64;}
        h.setAccessible(true);if((Integer)h.invoke(null)==1)n|=128;
        return n;
    }
}
