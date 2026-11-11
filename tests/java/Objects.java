public class Objects {
    static int trace;
    static Node saved;
    public static int record(int n) { trace = trace * 10 + n; return n; }
    interface Op { int apply(int n); }
    interface ChildOp extends Op {}
    static class Base {
        static int initialized = record(1);
        int value;
        Node inheritedNode;
        Base(int n) { value = n; }
        int get() { return value; }
        int calculate(int n) { return value + n; }
        private int hidden() { return value + 1; }
        int callHidden() { return hidden(); }
        static int baseStatic() { return 9; }
    }
    static class Child extends Base implements ChildOp {
        static int initialized = record(2);
        int value;
        Child(int n) { super(n); value = n + 10; }
        @Override int get() { return value * 2; }
        @Override public int apply(int n) { return super.calculate(n) + value; }
        int baseValue() { return super.value; }
        public int hidden() { return -999; }
    }
    static class Node {
        int value;
        Node next;
        Node(int n) { value = n; }
    }

    public static int dispatch(int n) {
        Child c = new Child(n);
        Base b = c;
        ChildOp op = c;
        return b.get() + op.apply(n) + c.baseValue() + c.value;
    }
    public static int inheritedStatic() { return Child.baseStatic() + trace * 100; }
    public static int initializeChild() { new Child(1); return trace; }
    public static int privateDispatch(int n) { return new Child(n).callHidden(); }
    public static int arrays(int n) {
        int[] ints = new int[n];
        byte[] bytes = new byte[n];
        short[] shorts = new short[n];
        char[] chars = new char[n];
        boolean[] bools = new boolean[n];
        int sum = 0;
        for (int i = 0; i < n; ++i) {
            ints[i] = i * 10000;
            bytes[i] = (byte)(i + 125);
            shorts[i] = (short)(i + 32765);
            chars[i] = (char)(i + 65533);
            bools[i] = (i & 1) == 0;
            sum += ints[i]++ + bytes[i] + shorts[i] + chars[i] + (bools[i] ? 1 : 0);
        }
        return sum + ints.length;
    }
    public static int references(int n) {
        Base[] values = new Child[2];
        Child c = new Child(n);
        values[0] = c;
        Object obj = values;
        Object[][] nested = new Object[2][];
        nested[0] = values;
        int bits = values[0] == c && values[1] == null ? 1 : 0;
        if (obj instanceof Base[]) bits += 2;
        if (obj instanceof Cloneable) bits += 4;
        if (obj instanceof java.io.Serializable) bits += 8;
        if (nested instanceof Object[]) bits += 16;
        if (new int[1] instanceof Object) bits += 32;
        return ((Base[])nested[0])[0].get() + bits;
    }
    public static Node make(int n) { return new Node(n); }
    public static int read(Node node) { return node.value; }
    public static int readObject(Object obj) { return ((Node)obj).value; }
    public static Node identity(Node node) { return node; }
    public static void keep(Node node) { saved = node; }
    public static int readSaved() { return saved.value; }
    public static void clearSaved() { saved = null; }
    public static int churn(int n) {
        Node anchor = new Node(7);
        int sum = 0;
        for (int i = 0; i < n; ++i) {
            Node temp = new Node(i);
            temp.next = anchor;
            sum += temp.next.value;
        }
        return sum + anchor.value;
    }
    public static Node chain(int n) {
        Node first = null;
        for (int i = 0; i < n; ++i) {
            Node node = new Node(i);
            node.next = first;
            first = node;
        }
        return first;
    }
    public static int chainSum(Node node) {
        int sum = 0;
        for (; node != null; node = node.next) sum += node.value;
        return sum;
    }
    public static int cycle() {
        Node a = new Node(10), b = new Node(20);
        a.next = b; b.next = a;
        return a.next.value + b.next.value;
    }
    public static int assignment(int n) {
        Node holder = new Node(1);
        Node[] array = new Node[1];
        return read(holder.next = new Node(n)) + read(array[0] = new Node(n + 1)) + holder.value++;
    }
    public static Node[] arrayRoot(int n) { return new Node[] { new Node(n), new Node(n + 1) }; }
    public static int arraySum(Node[] array) { return array[0].value + array[1].value; }
    public static int multi(int index) { return new int[2][index].length; }
    public static int matrix(int n) {
        int[][][] data = new int[n][2][3];
        int sum = 0;
        for (int i = 0; i < n; ++i) {
            data[i][1][2] = i + 1;
            sum += data[i][1][2];
        }
        Node[][] partial = new Node[2][];
        partial[1] = new Node[] {new Node(9)};
        return sum + partial[1][0].value;
    }
    public static int emptyNegative(int n) { return new int[0][n].length; }
    public static int index(int index) { int[] array = new int[2]; return array[index]; }
    public static int negative(int n) { return new byte[n].length; }
    public static int nullField() { Node node = null; return node.value; }
    public static int nullCall() { Base obj = null; return obj.get(); }
    public static int nullArray() { int[] array = null; return array.length; }
    public static int badStore() { Base[] values = new Child[1]; values[0] = new Base(1); return 0; }
    public static int badCast() { Object obj = new Base(1); return ((Child)obj).get(); }
    public static int nullCast() { Object obj = null; return (Node)obj == null && !(obj instanceof Node) ? 1 : 0; }

    static native int collectNative();
    static native int probe(Node node);
    static native Node roundTrip(Node node);
    private static int add(Node node, int value) { return node.value + value; }
    public static int suspendedOperand() { return add(new Node(40), collectNative()); }
    public static int nativeRoot(int n) { return probe(new Node(n)); }
    public static int nativeReference(int n) { return roundTrip(new Node(n)).value; }
    public static int makeAndCollect(int n) { Node node = new Node(n); collectNative(); return node.value; }
    public static int inheritedRoot() {
        Base base = new Child(1);
        base.inheritedNode = new Node(42);
        collectNative();
        return base.inheritedNode.value;
    }
}
