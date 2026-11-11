package jbv.runtime;
import java.util.*;
import java.util.function.*;
import java.util.stream.*;

/** Every stream is a pull pipeline of these stages over boxed values; Int/Long/DoublePipe wrap one.
 * Element kinds: 0 reference, 1 int, 2 long, 3 double. A map code is from*4+to (the functional
 * interface follows from the pair), 16 keeps the value, 17..19 widen int/long to long/double. */
@SuppressWarnings({"unchecked","rawtypes"})
public final class Pipe implements Stream, Iterator, Runnable {
    static final int ITERABLE=0,ITER=1,ARRAY=2,RANGE=3,ITERATE=4,GENERATE=5,CONCAT=6,FILTER=7,MAP=8,FLAT=9,PEEK=10,
        DISTINCT=11,SORTED=12,LIMIT=13,SKIP=14,TAKE=15,DROP=16,MULTI=17;
    final Pipe up, head; final int op, kind, code; final Object f, g;
    long n, end; Object state, inner, value; boolean ready, done, linked; ArrayList<Runnable> closers;

    Pipe(Pipe up,int op,int kind,int code,Object f,Object g){this.up=up;this.head=up==null||op==CONCAT?this:up.head;this.op=op;this.kind=kind;this.code=code;this.f=f;this.g=g;}

    // ---- sources ----
    public static Stream of(Iterable source){return new Pipe(null,ITERABLE,0,0,Objects.requireNonNull(source),null);}
    public static Pipe iterator(int kind,Iterator it){return new Pipe(null,ITER,kind,0,it,null);}
    public static Object array(int kind,Object array,int from,int to){
        int length=kind==0?((Object[])array).length:kind==1?((int[])array).length:kind==2?((long[])array).length:((double[])array).length;
        if(from<0||to>length||from>to)throw new ArrayIndexOutOfBoundsException("origin("+from+") > fence("+to+")");
        Pipe p=new Pipe(null,ARRAY,kind,0,array,null);p.n=from;p.end=to;return wrap(p);}
    /** Values lo..last inclusive; none if lo > last. */
    public static Object range(int kind,long lo,long last,boolean empty){Pipe p=new Pipe(null,RANGE,kind,0,null,null);p.n=lo;p.end=last;p.done=empty||lo>last;return wrap(p);}
    public static Object iterate(int kind,Object seed,Object hasNext,Object next){Objects.requireNonNull(next);Pipe p=new Pipe(null,ITERATE,kind,kind*5,next,hasNext);p.state=seed;return wrap(p);}
    public static Object generate(int kind,Object supplier){return wrap(new Pipe(null,GENERATE,kind,0,Objects.requireNonNull(supplier),null));}
    public static Object concat(int kind,Object a,Object b){
        Pipe x=pipe(a),y=pipe(b);x.begin();y.begin();Pipe p=new Pipe(x,CONCAT,kind,0,null,y);p.onClose(x);p.onClose(y);return wrap(p);}
    public static Object empty(int kind){return range(kind,0,0,true);}
    public static Object wrap(Pipe p){return p.kind==0?p:p.kind==1?new IntPipe(p):p.kind==2?(Object)new LongPipe(p):new DoublePipe(p);}
    static Pipe pipe(Object s){
        if(s instanceof Pipe)return (Pipe)s;if(s instanceof IntPipe)return ((IntPipe)s).p;
        if(s instanceof LongPipe)return ((LongPipe)s).p;if(s instanceof DoublePipe)return ((DoublePipe)s).p;
        return iterator(0,((BaseStream)s).iterator());}

    // ---- function calls by code ----
    static Object call(int code,Object f,Object v){
        switch(code){
        case 0:return ((Function)f).apply(v);
        case 1:return ((ToIntFunction)f).applyAsInt(v);
        case 2:return ((ToLongFunction)f).applyAsLong(v);
        case 3:return ((ToDoubleFunction)f).applyAsDouble(v);
        case 4:return ((IntFunction)f).apply((Integer)v);
        case 5:return ((IntUnaryOperator)f).applyAsInt((Integer)v);
        case 6:return ((IntToLongFunction)f).applyAsLong((Integer)v);
        case 7:return ((IntToDoubleFunction)f).applyAsDouble((Integer)v);
        case 8:return ((LongFunction)f).apply((Long)v);
        case 9:return ((LongToIntFunction)f).applyAsInt((Long)v);
        case 10:return ((LongUnaryOperator)f).applyAsLong((Long)v);
        case 11:return ((LongToDoubleFunction)f).applyAsDouble((Long)v);
        case 12:return ((DoubleFunction)f).apply((Double)v);
        case 13:return ((DoubleToIntFunction)f).applyAsInt((Double)v);
        case 14:return ((DoubleToLongFunction)f).applyAsLong((Double)v);
        case 15:return ((DoubleUnaryOperator)f).applyAsDouble((Double)v);
        case 17:return (long)(Integer)v;
        case 18:return (double)(Integer)v;
        case 19:return (double)(Long)v;
        default:return v;
        }
    }
    static boolean test(int kind,Object f,Object v){
        return kind==0?((Predicate)f).test(v):kind==1?((IntPredicate)f).test((Integer)v):kind==2?((LongPredicate)f).test((Long)v):((DoublePredicate)f).test((Double)v);}
    static void accept(int kind,Object f,Object v){
        if(kind==0)((Consumer)f).accept(v);else if(kind==1)((IntConsumer)f).accept((Integer)v);else if(kind==2)((LongConsumer)f).accept((Long)v);else ((DoubleConsumer)f).accept((Double)v);}
    static Object get(int kind,Object f){
        return kind==0?((Supplier)f).get():kind==1?(Object)((IntSupplier)f).getAsInt():kind==2?(Object)((LongSupplier)f).getAsLong():(Object)((DoubleSupplier)f).getAsDouble();}
    static Object element(Object a,int kind,int i){return kind==0?((Object[])a)[i]:kind==1?(Object)((int[])a)[i]:kind==2?(Object)((long[])a)[i]:(Object)((double[])a)[i];}

    // ---- pulling ----
    /** The next value of this stage into value; false at the end. */
    boolean pull(){
        for(;;)switch(op){
        case ITERABLE:case ITER:{
            Iterator it=(Iterator)(state!=null?state:(state=op==ITER?f:((Iterable)f).iterator()));
            if(!it.hasNext())return false;value=it.next();return true;}
        case ARRAY:if(n>=end)return false;value=element(f,kind,(int)n++);return true;
        case RANGE:if(done)return false;value=kind==1?(Object)Integer.valueOf((int)n):(Object)Long.valueOf(n);if(n==end)done=true;else n++;return true;
        case ITERATE:
            if(done)return false;
            value=n++==0?state:call(code,f,value);
            if(g!=null&&!test(kind,g,value)){done=true;return false;}
            return true;
        case GENERATE:value=get(kind,f);return true;
        case CONCAT:
            if(!done){if(up.pull()){value=up.value;return true;}done=true;}
            if(((Pipe)g).pull()){value=((Pipe)g).value;return true;}return false;
        case FILTER:while(up.pull())if(test(up.kind,f,up.value)){value=up.value;return true;}return false;
        case MAP:if(!up.pull())return false;value=call(code,f,up.value);return true;
        case FLAT:
            for(;;){
                if(state!=null){if(((Iterator)state).hasNext()){value=((Iterator)state).next();return true;}((BaseStream)inner).close();state=inner=null;}
                if(!up.pull())return false;
                Object s=call(code,f,up.value);if(s!=null){inner=s;state=((BaseStream)s).iterator();}
            }
        case PEEK:if(!up.pull())return false;value=up.value;accept(up.kind,f,value);return true;
        case DISTINCT:
            if(state==null)state=new HashSet();
            while(up.pull())if(((HashSet)state).add(up.value)){value=up.value;return true;}return false;
        case SORTED:
            if(state==null){ArrayList all=new ArrayList();while(up.pull())all.add(up.value);Object[] a=all.toArray();Arrays.sort(a,(Comparator)f);state=a;}
            if(n>=((Object[])state).length)return false;value=((Object[])state)[(int)n++];return true;
        case LIMIT:if(n>=end||!up.pull())return false;n++;value=up.value;return true;
        case SKIP:for(;n<end;n++)if(!up.pull())return false;if(!up.pull())return false;value=up.value;return true;
        case TAKE:if(done||!up.pull())return false;if(!test(kind,f,up.value)){done=true;return false;}value=up.value;return true;
        case DROP:
            while(up.pull())if(done||!test(kind,f,up.value)){done=true;value=up.value;return true;}return false;
        default:{   // MULTI: the values one element gives, buffered
            Buffer b=(Buffer)(state!=null?state:(state=new Buffer()));
            while(n>=b.items.size()){b.items.clear();n=0;if(!up.pull())return false;((BiConsumer)f).accept(up.value,b);}
            value=b.items.get((int)n++);return true;}
        }
    }
    /** Marks this stage consumed: one terminal operation or one more stage per stream. */
    void begin(){if(linked)throw new IllegalStateException("stream has already been operated upon or closed");linked=true;}
    Pipe stage(int op,int kind,int code,Object f){begin();Pipe p=new Pipe(this,op,kind,code,f,null);return p;}
    Pipe slice(int op,long count){if(count<0)throw new IllegalArgumentException(Long.toString(count));Pipe p=stage(op,kind,0,null);p.end=count;return p;}
    Pipe check(Object f){Objects.requireNonNull(f);return this;}
    /** The element count if known without running the pipeline (as the JDK's sized streams), else -1. */
    long size(){
        switch(op){
        case ITERABLE:return f instanceof Collection?((Collection)f).size():-1;
        case ARRAY:return end-n;
        case RANGE:return done?0:end-n>=0&&end-n<Long.MAX_VALUE?end-n+1:-1;
        case MAP:case PEEK:case SORTED:return up.size();
        case LIMIT:{long s=up.size();return s<0?-1:Math.min(s,end);}
        case SKIP:{long s=up.size();return s<0?-1:Math.max(0,s-end);}
        default:return -1;
        }
    }

    // ---- intermediate operations ----
    public Stream filter(Predicate p){return check(p).stage(FILTER,0,0,p);}
    public Stream map(Function m){return check(m).stage(MAP,0,0,m);}
    public IntStream mapToInt(ToIntFunction m){return new IntPipe(check(m).stage(MAP,1,1,m));}
    public LongStream mapToLong(ToLongFunction m){return new LongPipe(check(m).stage(MAP,2,2,m));}
    public DoubleStream mapToDouble(ToDoubleFunction m){return new DoublePipe(check(m).stage(MAP,3,3,m));}
    public Stream flatMap(Function m){return check(m).stage(FLAT,0,0,m);}
    public IntStream flatMapToInt(Function m){return new IntPipe(check(m).stage(FLAT,1,0,m));}
    public LongStream flatMapToLong(Function m){return new LongPipe(check(m).stage(FLAT,2,0,m));}
    public DoubleStream flatMapToDouble(Function m){return new DoublePipe(check(m).stage(FLAT,3,0,m));}
    public Stream mapMulti(BiConsumer m){return check(m).stage(MULTI,0,0,m);}
    public Stream distinct(){return stage(DISTINCT,0,0,null);}
    public Stream sorted(){return stage(SORTED,0,0,null);}
    public Stream sorted(Comparator c){return check(c).stage(SORTED,0,0,c);}
    public Stream peek(Consumer c){return check(c).stage(PEEK,0,0,c);}
    public Stream limit(long n){return slice(LIMIT,n);}
    public Stream skip(long n){return slice(SKIP,n);}
    public Stream takeWhile(Predicate p){return check(p).stage(TAKE,0,0,p);}
    public Stream dropWhile(Predicate p){return check(p).stage(DROP,0,0,p);}
    public boolean isParallel(){return false;}
    public Stream sequential(){return this;}
    public Stream parallel(){return this;}
    public Stream unordered(){return this;}
    public Stream onClose(Runnable r){Objects.requireNonNull(r);if(head.closers==null)head.closers=new ArrayList();head.closers.add(r);return this;}
    public void close(){
        linked=true;ArrayList<Runnable> all=head.closers;head.closers=null;if(all==null)return;
        RuntimeException first=null;
        for(Runnable r:all)try{r.run();}catch(RuntimeException e){if(first==null)first=e;else if(e!=first)first.addSuppressed(e);}
        if(first!=null)throw first;
    }
    public void run(){close();}

    // ---- terminal operations ----
    public void forEach(Consumer c){each(c);}
    public void forEachOrdered(Consumer c){each(c);}
    void each(Object c){Objects.requireNonNull(c);begin();while(pull())accept(kind,c,value);}
    ArrayList list(){begin();long s=size();ArrayList a=new ArrayList(s>0&&s<1<<20?(int)s:10);while(pull())a.add(value);return a;}
    public Object[] toArray(){return list().toArray();}
    public Object[] toArray(IntFunction generator){
        ArrayList a=list();Object[] r=(Object[])generator.apply(a.size());
        if(r.length!=a.size())throw new IllegalStateException("Begin size "+a.size()+" is not equal to fixed size "+r.length);
        for(int i=0;i<r.length;i++)r[i]=a.get(i);return r;}
    public List toList(){return java.util.Collections.unmodifiableList(list());}
    public Object reduce(Object identity,BinaryOperator op){begin();Object r=identity;while(pull())r=op.apply(r,value);return r;}
    public Optional reduce(BinaryOperator op){
        Objects.requireNonNull(op);begin();if(!pull())return Optional.empty();Object r=value;while(pull())r=op.apply(r,value);return Optional.of(r);}
    public Object reduce(Object identity,BiFunction acc,BinaryOperator combiner){begin();Object r=identity;while(pull())r=acc.apply(r,value);return r;}
    public Object collect(Supplier s,BiConsumer acc,BiConsumer combiner){Object r=s.get();begin();while(pull())acc.accept(r,value);return r;}
    public Object collect(Collector c){
        Object a=c.supplier().get();BiConsumer acc=c.accumulator();begin();while(pull())acc.accept(a,value);return Collect.finish(c,a);}
    public Optional min(Comparator c){return best(c,false);}
    public Optional max(Comparator c){return best(c,true);}
    Optional best(Comparator c,boolean max){
        Objects.requireNonNull(c);begin();if(!pull())return Optional.empty();Object r=value;
        while(pull()){int d=c.compare(r,value);if(max?d<0:d>0)r=value;}
        return Optional.of(r);}
    public long count(){begin();long s=size();if(s>=0)return s;s=0;while(pull())s++;return s;}
    public boolean anyMatch(Predicate p){return match(p,true,true);}
    public boolean allMatch(Predicate p){return match(p,false,false);}
    public boolean noneMatch(Predicate p){return match(p,true,false);}
    boolean match(Object p,boolean stopOn,boolean result){Objects.requireNonNull(p);begin();while(pull())if(test(kind,p,value)==stopOn)return result;return !result;}
    public Optional findFirst(){begin();return pull()?Optional.of(value):Optional.empty();}
    public Optional findAny(){return findFirst();}
    public Iterator iterator(){begin();return this;}
    public boolean hasNext(){if(!ready)ready=pull();return ready;}
    public Object next(){if(!hasNext())throw new NoSuchElementException();ready=false;return value;}

    /** Collects values: the mapMulti buffer and Stream.builder(). */
    static final class Buffer implements Stream.Builder {
        final ArrayList items=new ArrayList();boolean built;
        public void accept(Object v){if(built)throw new IllegalStateException();items.add(v);}
        public Stream build(){if(built)throw new IllegalStateException();built=true;return new Pipe(null,ITERABLE,0,0,items,null);}
    }
    public static Stream.Builder builder(){return new Buffer();}
}
