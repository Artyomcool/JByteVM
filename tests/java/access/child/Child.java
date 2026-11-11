package access.child;
public class Child extends access.base.Api {
    public int hidden(){return 97;}
    public int read(Child other){return other.protectedValue;}
}
