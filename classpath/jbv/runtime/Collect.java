package jbv.runtime;
import java.util.*;
import java.util.function.*;
import java.util.stream.*;

/** Every Collectors collector: one class, a kind, up to four operands. It is its own supplier,
 * accumulator, combiner and finisher; Collector.of collectors hand out the user's functions. */
@SuppressWarnings({"unchecked","rawtypes"})
public final class Collect implements Collector,Supplier,BiConsumer,BinaryOperator,Function {
    public static final int COLL=0,LIST=1,SET=2,ULIST=3,USET=4,JOIN=5,MAPPING=6,FILTERING=7,FLATMAPPING=8,THEN=9,COUNT=10,
        BEST=11,STATS=12,REDUCE=13,GROUP=14,PARTITION=15,TOMAP=16,TEE=17,CUSTOM=18;
    static final Set ID=java.util.Collections.unmodifiableSet(EnumSet.of(Characteristics.IDENTITY_FINISH)),NONE=java.util.Collections.emptySet();
    final int kind,code; final Object a,b,c,d; final Set chars;

    public Collect(int kind,int code,Object a,Object b,Object c,Object d){
        this.kind=kind;this.code=code;this.a=a;this.b=b;this.c=c;this.d=d;
        boolean id=kind<=SET||kind==TOMAP&&code==0||kind==GROUP&&identity((Collector)c)||kind>=MAPPING&&kind<=FLATMAPPING&&identity((Collector)b);
        chars=id?ID:NONE;}
    public Collect(Supplier s,BiConsumer acc,BinaryOperator combiner,Function finisher,Characteristics[] ch,boolean id){
        Objects.requireNonNull(s);Objects.requireNonNull(acc);Objects.requireNonNull(combiner);if(!id)Objects.requireNonNull(finisher);
        kind=CUSTOM;code=0;a=s;b=acc;c=combiner;d=finisher;
        EnumSet set=EnumSet.noneOf(Characteristics.class);for(Characteristics x:ch)set.add(Objects.requireNonNull(x));if(id)set.add(Characteristics.IDENTITY_FINISH);
        chars=java.util.Collections.unmodifiableSet(set);}

    static boolean identity(Collector c){return c.characteristics().contains(Characteristics.IDENTITY_FINISH);}
    public static Object finish(Collector c,Object box){return c instanceof Collect?((Collect)c).apply(box):identity(c)?box:c.finisher().apply(box);}
    static Object start(Collector c){return c.supplier().get();}
    static void add(Collector c,Object box,Object t){c.accumulator().accept(box,t);}

    public Supplier supplier(){return kind==CUSTOM?(Supplier)a:this;}
    public BiConsumer accumulator(){return kind==CUSTOM?(BiConsumer)b:this;}
    public BinaryOperator combiner(){return kind==CUSTOM?(BinaryOperator)c:this;}
    public Function finisher(){return kind==CUSTOM&&d!=null?(Function)d:this;}
    public Set characteristics(){return chars;}

    /** A new container. */
    public Object get(){
        switch(kind){
        case COLL:return ((Supplier)a).get();
        case LIST:case ULIST:case JOIN:return new ArrayList();
        case SET:case USET:return new HashSet();
        case MAPPING:case FILTERING:case FLATMAPPING:return start((Collector)b);
        case THEN:return start((Collector)a);
        case COUNT:return new long[1];
        case BEST:return new Object[2];
        case REDUCE:return new Object[]{a,code==1?Boolean.TRUE:null};
        case STATS:return code<3?new IntSummaryStatistics():code<6?new LongSummaryStatistics():(Object)new DoubleSummaryStatistics();
        case GROUP:case TOMAP:{Object f=kind==GROUP?b:d;return f==null?new HashMap():((Supplier)f).get();}
        case PARTITION:return new Object[]{start((Collector)c),start((Collector)c)};
        case TEE:return new Object[]{start((Collector)a),start((Collector)b)};
        default:return ((Supplier)a).get();
        }
    }
    /** Adds t to the container. */
    public void accept(Object box,Object t){
        switch(kind){
        case COLL:case LIST:case SET:case ULIST:case USET:((Collection)box).add(t);return;
        case JOIN:((ArrayList)box).add(String.valueOf(t));return;
        case MAPPING:add((Collector)b,box,((Function)a).apply(t));return;
        case FILTERING:if(((Predicate)a).test(t))add((Collector)b,box,t);return;
        case FLATMAPPING:{
            BaseStream s=(BaseStream)((Function)a).apply(t);if(s==null)return;
            try{BiConsumer acc=((Collector)b).accumulator();for(Iterator it=s.iterator();it.hasNext();)acc.accept(box,it.next());}finally{s.close();}
            return;}
        case THEN:add((Collector)a,box,t);return;
        case COUNT:((long[])box)[0]++;return;
        case BEST:{Object[] o=(Object[])box;if(o[1]==null){o[0]=t;o[1]=Boolean.TRUE;}else{int r=((Comparator)a).compare(o[0],t);if(code==1?r<0:r>0)o[0]=t;}return;}
        case REDUCE:{Object[] o=(Object[])box;Object v=b==null?t:((Function)b).apply(t);if(o[1]==null){o[0]=v;o[1]=Boolean.TRUE;}else o[0]=((BinaryOperator)c).apply(o[0],v);return;}
        case STATS:
            if(code<3)((IntSummaryStatistics)box).accept(((ToIntFunction)a).applyAsInt(t));
            else if(code<6)((LongSummaryStatistics)box).accept(((ToLongFunction)a).applyAsLong(t));
            else ((DoubleSummaryStatistics)box).accept(((ToDoubleFunction)a).applyAsDouble(t));
            return;
        case GROUP:{
            Object k=Objects.requireNonNull(((Function)a).apply(t),"element cannot be mapped to a null key");Map m=(Map)box;
            Object x=m.get(k);if(x==null){x=start((Collector)c);m.put(k,x);}add((Collector)c,x,t);return;}
        case PARTITION:add((Collector)c,((Object[])box)[((Predicate)a).test(t)?1:0],t);return;
        case TOMAP:{
            Object k=((Function)a).apply(t),v=Objects.requireNonNull(((Function)b).apply(t));Map m=(Map)box;
            if(c!=null){m.merge(k,v,(BiFunction)c);return;}
            Object u=m.putIfAbsent(k,v);
            if(u!=null)throw new IllegalStateException("Duplicate key "+k+" (attempted merging values "+u+" and "+v+")");
            return;}
        case TEE:add((Collector)a,((Object[])box)[0],t);add((Collector)b,((Object[])box)[1],t);return;
        default:((BiConsumer)b).accept(box,t);
        }
    }
    /** The result of a container. */
    public Object apply(Object box){
        switch(kind){
        case ULIST:return List.copyOf((Collection)box);
        case USET:return Set.copyOf((Collection)box);
        case JOIN:{
            ArrayList<String> all=(ArrayList<String>)box;StringBuilder s=new StringBuilder((String)b);
            for(int i=0;i<all.size();i++){if(i>0)s.append((String)a);s.append(all.get(i));}
            return s.append((String)c).toString();}
        case MAPPING:case FILTERING:case FLATMAPPING:return finish((Collector)b,box);
        case THEN:return ((Function)b).apply(finish((Collector)a,box));
        case COUNT:return ((long[])box)[0];
        case BEST:return Optional.ofNullable(((Object[])box)[0]);
        case REDUCE:return code==1?((Object[])box)[0]:Optional.ofNullable(((Object[])box)[0]);
        case STATS:{
            int v=code%3;if(v==2)return box;
            if(code<3){IntSummaryStatistics s=(IntSummaryStatistics)box;return v==0?(Object)(int)s.getSum():(Object)s.getAverage();}
            if(code<6){LongSummaryStatistics s=(LongSummaryStatistics)box;return v==0?(Object)s.getSum():(Object)s.getAverage();}
            DoubleSummaryStatistics s=(DoubleSummaryStatistics)box;return v==0?s.getSum():s.getAverage();}
        case GROUP:{
            Collector ds=(Collector)c;if(!identity(ds))for(Object e:((Map)box).entrySet())((Map.Entry)e).setValue(finish(ds,((Map.Entry)e).getValue()));
            return box;}
        case PARTITION:{
            Object[] o=(Object[])box;Map m=new LinkedHashMap();Collector ds=(Collector)c;
            m.put(Boolean.FALSE,finish(ds,o[0]));m.put(Boolean.TRUE,finish(ds,o[1]));return java.util.Collections.unmodifiableMap(m);}
        case TOMAP:return code==1?Map.copyOf((Map)box):box;
        case TEE:{Object[] o=(Object[])box;return ((BiFunction)c).apply(finish((Collector)a,o[0]),finish((Collector)b,o[1]));}
        case CUSTOM:return d==null?box:((Function)d).apply(box);
        default:return box;
        }
    }
    /** Containers are never merged: streams here are sequential. */
    public Object apply(Object x,Object y){throw new UnsupportedOperationException();}
}
