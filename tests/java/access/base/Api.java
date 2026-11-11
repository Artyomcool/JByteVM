package access.base;
public class Api {
    public static int field=17;
    public static int call(){return 23;}
    public int item=31;
    protected int protectedValue=41;
    int hidden(){return 53;}
    public int dispatch(){return hidden();}
    public int inst(){return 67;}
}
