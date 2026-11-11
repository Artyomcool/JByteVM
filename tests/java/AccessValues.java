import access.base.Api;
import access.child.Child;
public class AccessValues {
    private int value=7;
    private int secret(){return value;}
    static class A {private int value=11;private int secret(){return value;}static int read(B b){return b.value;}}
    static class B {private int value=13;static int read(A a){return a.secret();}}
    public static int positive(int n){Child c=new Child();return c.dispatch()+c.hidden()+c.read(c)+new AccessValues().secret()+A.read(new B())+B.read(new A())+n;}
    public static int field(int n){try{return Api.field+n;}catch(IllegalAccessError e){return 1;}catch(NoSuchFieldError e){return 2;}catch(IncompatibleClassChangeError e){return 3;}}
    public static int method(int n){try{return Api.call()+n;}catch(IllegalAccessError e){return 4;}catch(NoSuchMethodError e){return 5;}catch(IncompatibleClassChangeError e){return 6;}}
    public static int wrongStatic(int n){try{return Api.call()+n;}catch(IncompatibleClassChangeError e){return 8;}}
}
