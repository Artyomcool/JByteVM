public class Defaults {
    static int log;
    static int mark(int n) { log = log * 10 + n; return n; }
    interface Root {
        int INIT = mark(1);
        private int secret() { return 10; }
        default int value() { return secret() + 1; }
    }
    interface Left extends Root { }
    interface Right extends Root {
        int INIT = mark(2);
        default int value() { return Root.super.value() + 2; }
    }
    interface Silent {
        int INIT = mark(9);
        int value();
    }
    interface Leaf extends Right {
        int INIT = mark(8);
    }
    static class Diamond implements Left, Leaf {
        static int INIT = mark(3);
    }
    static class Override extends Diamond {
        public int value() { return super.value() + 4; }
    }
    static class Parent { public int value() { return 29; } }
    static class ClassWins extends Parent implements Right, Silent { }
    interface AbstractAgain extends Right { int value(); }
    static class Concrete implements AbstractAgain { public int value() { return 37; } }
    static class Explicit implements Left, Silent { public int value() { return Left.super.value() + 5; } }
    public static int init(int n) { new Diamond(); return log; }
    public static int dispatch(int n) {
        Root a = new Diamond(), b = new Override(), c = new ClassWins(), d = new Concrete(), e = new Explicit();
        return a.value() + b.value() + c.value() + d.value() + e.value() + n;
    }
    public static int direct(int n) { return new Diamond().value() + new Override().value() + n; }
    public static int interfaceInit(int n) { return Leaf.INIT * 100 + log; }
}
