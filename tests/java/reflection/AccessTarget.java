package reflection;
public class AccessTarget {
    private int secret=13;
    protected int value(){return 17;}
    public AccessTarget(){}
    public static Class<?> hidden(){return Hidden.class;}
}
class Hidden {public static int run(){return 1;}}
