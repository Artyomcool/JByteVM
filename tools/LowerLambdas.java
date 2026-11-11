import java.lang.classfile.*;
import java.lang.classfile.attribute.*;
import java.lang.classfile.instruction.*;
import java.lang.constant.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import static java.lang.constant.ConstantDescs.*;
import static java.lang.classfile.ClassFile.*;

/** Build-time invokedynamic lowering: LambdaMetafactory sites become ordinary classes; record
 * ObjectMethods and pattern-switch SwitchBootstraps sites become private static helper methods.
 * Never runs the application's code. */
public class LowerLambdas {
    static ClassFile cf;
    static final Map<String,ClassModel> models=new LinkedHashMap<>();
    static final Map<String,List<Lambda>> plans=new LinkedHashMap<>();
    static final Map<String,List<ClassDesc>> nests=new HashMap<>();
    static final Map<String,byte[]> output=new LinkedHashMap<>();
    static String internal(ClassDesc d){return d.descriptorString().substring(1,d.descriptorString().length()-1);}
    static TypeKind kind(ClassDesc d){return TypeKind.fromDescriptor(d.descriptorString());}
    static int slots(ClassDesc d){return d.equals(CD_long)||d.equals(CD_double)?2:1;}
    record Lambda(ClassDesc owner,ClassDesc generated,ClassDesc host,String name,MethodTypeDesc factory,
                  MethodTypeDesc sam,MethodTypeDesc instantiated,DirectMethodHandleDesc impl,
                  List<ClassDesc> interfaces,List<MethodTypeDesc> bridges,String specialBridge) {}
    /** An indy site replaced by a private static helper in its own class (records, pattern switches). */
    record Inline(String name,MethodTypeDesc type,java.util.function.Consumer<CodeBuilder> body) {}
    static final ClassDesc OBJECTS=ClassDesc.of("java.util.Objects"),CD_StringBuilder=ClassDesc.of("java.lang.StringBuilder"),
        CD_Character=ClassDesc.of("java.lang.Character");
    static Object plan(ClassModel model,InvokeDynamicInstruction instruction,int lambdas,int inlines){
        var bootstrap=instruction.bootstrapMethod();
        String site=bootstrap.owner().packageName()+"."+bootstrap.owner().displayName()+"."+bootstrap.methodName(),where=" in "+model.thisClass().asInternalName(),helper="$jbv$indy$"+inlines;
        if(site.equals("java.lang.invoke.LambdaMetafactory.metafactory")||site.equals("java.lang.invoke.LambdaMetafactory.altMetafactory"))return parse(model,instruction,lambdas);
        if(site.startsWith("java.lang.invoke.StringConcatFactory."))throw new IllegalArgumentException("String concatenation uses invokedynamic"+where+"; compile with -XDstringConcat=inline");
        boolean records=site.equals("java.lang.runtime.ObjectMethods.bootstrap");
        if(!records&&!site.equals("java.lang.runtime.SwitchBootstraps.typeSwitch")&&!site.equals("java.lang.runtime.SwitchBootstraps.enumSwitch"))
            throw new IllegalArgumentException("Unsupported invokedynamic bootstrap "+site+where+"; only LambdaMetafactory, ObjectMethods.bootstrap and SwitchBootstraps.typeSwitch/enumSwitch are supported");
        if(model.methods().stream().anyMatch(m->m.methodName().equalsString(helper)))throw new IllegalArgumentException("Helper name collision: "+helper+where);
        return records?records(instruction,helper,where):switches(instruction,helper,where);
    }
    /** Simple name exactly as Class.getSimpleName() derives it from the InnerClasses attribute. */
    static String simpleName(ClassDesc c){
        ClassModel m=models.get(internal(c));if(m==null)throw new IllegalArgumentException("Record class is missing from input: "+internal(c));
        for(InnerClassInfo i:m.findAttribute(Attributes.innerClasses()).map(InnerClassesAttribute::classes).orElse(List.of()))
            if(i.innerClass().asInternalName().equals(internal(c)))return i.innerName().map(n->n.stringValue()).orElse("");
        return internal(c).substring(internal(c).lastIndexOf('/')+1);
    }
    static ClassDesc component(CodeBuilder code,int local,DirectMethodHandleDesc getter){
        ClassDesc type=getter.invocationType().returnType();code.aload(local);
        if(getter.kind()==DirectMethodHandleDesc.Kind.GETTER)code.getfield(getter.owner(),getter.methodName(),type);
        else code.invokevirtual(getter.owner(),getter.methodName(),MethodTypeDesc.of(type));
        return type;
    }
    /** ObjectMethods.bootstrap with the evaluation order of the JDK's method-handle trees:
     * equals tests components last to first; hashCode is 31*h+hash(c) from 0, first to last. */
    static Inline records(InvokeDynamicInstruction indy,String helper,String where){
        List<ConstantDesc> args=indy.bootstrapArgs();
        if(args.size()<2||!(args.get(0) instanceof ClassDesc record)||!(args.get(1) instanceof String names))throw new IllegalArgumentException("Malformed ObjectMethods.bootstrap arguments"+where);
        List<DirectMethodHandleDesc> getters=new ArrayList<>();
        for(ConstantDesc a:args.subList(2,args.size())){
            if(!(a instanceof DirectMethodHandleDesc g)||!(g.kind()==DirectMethodHandleDesc.Kind.GETTER||g.kind()==DirectMethodHandleDesc.Kind.VIRTUAL&&g.invocationType().parameterCount()==1))
                throw new IllegalArgumentException("Unsupported record component accessor "+a+where);
            getters.add(g);
        }
        String method=indy.name().stringValue();MethodTypeDesc type=indy.typeSymbol();
        MethodTypeDesc expected=switch(method){case "equals"->MethodTypeDesc.of(CD_boolean,record,CD_Object);case "hashCode"->MethodTypeDesc.of(CD_int,record);
            case "toString"->MethodTypeDesc.of(CD_String,record);default->throw new IllegalArgumentException("Unknown ObjectMethods method "+method+where);};
        if(!type.equals(expected))throw new IllegalArgumentException("Bad ObjectMethods method type "+type+where);
        if(method.equals("equals"))return new Inline(helper,type,code->{
            Label notSame=code.newLabel(),instance=code.newLabel(),fail=code.newLabel();
            code.aload(0).aload(1).if_acmpne(notSame).iconst_1().ireturn();
            code.labelBinding(notSame).aload(1).instanceOf(record).ifne(instance).iconst_0().ireturn();
            code.labelBinding(instance).aload(1).checkcast(record).astore(2);
            for(DirectMethodHandleDesc g:getters.reversed()){
                ClassDesc t=component(code,0,g);component(code,2,g);
                switch(t.descriptorString()){
                    case "J"->code.lcmp().ifne(fail);
                    case "F","D"->code.invokestatic(wrapper(t),"compare",MethodTypeDesc.of(CD_int,t,t)).ifne(fail);
                    case "Z","B","C","S","I"->code.if_icmpne(fail);
                    default->code.invokestatic(OBJECTS,"equals",MethodTypeDesc.of(CD_boolean,CD_Object,CD_Object)).ifeq(fail);
                }
            }
            code.iconst_1().ireturn().labelBinding(fail).iconst_0().ireturn();
        });
        if(method.equals("hashCode"))return new Inline(helper,type,code->{
            code.iconst_0();
            for(DirectMethodHandleDesc g:getters){
                code.bipush(31).imul();ClassDesc t=component(code,0,g);
                if(t.isPrimitive())code.invokestatic(wrapper(t),"hashCode",MethodTypeDesc.of(CD_int,t));
                else code.invokestatic(OBJECTS,"hashCode",MethodTypeDesc.of(CD_int,CD_Object));
                code.iadd();
            }
            code.ireturn();
        });
        List<String> list=names.isEmpty()?List.of():List.of(names.split(";"));
        if(list.size()!=getters.size())throw new IllegalArgumentException("Record component names and accessors do not match"+where);
        String simple=simpleName(record);
        return new Inline(helper,type,code->{
            if(getters.isEmpty()){code.ldc(simple+"[]").areturn();return;}
            code.new_(CD_StringBuilder).dup().invokespecial(CD_StringBuilder,"<init>",MethodTypeDesc.of(CD_void));
            for(int i=0;i<getters.size();i++){
                code.ldc((i==0?simple+"[":", ")+list.get(i)+"=").invokevirtual(CD_StringBuilder,"append",MethodTypeDesc.of(CD_StringBuilder,CD_String));
                ClassDesc t=component(code,0,getters.get(i));
                // StringConcatFactory prints byte/short as int and references via String.valueOf.
                ClassDesc arg=switch(t.descriptorString()){case "B","S","I"->CD_int;case "Z","C","J","F","D"->t;default->CD_Object;};
                code.invokevirtual(CD_StringBuilder,"append",MethodTypeDesc.of(CD_StringBuilder,arg));
            }
            code.ldc("]").invokevirtual(CD_StringBuilder,"append",MethodTypeDesc.of(CD_StringBuilder,CD_String))
                .invokevirtual(CD_StringBuilder,"toString",MethodTypeDesc.of(CD_String)).areturn();
        });
    }
    static boolean invokes(ConstantDesc c,String owner,String name,int arguments){
        return c instanceof DynamicConstantDesc<?> d&&d.bootstrapMethod().owner().equals(ClassDesc.of("java.lang.invoke.ConstantBootstraps"))&&d.bootstrapMethod().methodName().equals("invoke")
            &&d.bootstrapArgs().length==arguments+1&&d.bootstrapArgs()[0] instanceof DirectMethodHandleDesc m&&m.owner().equals(ClassDesc.of(owner))&&m.methodName().equals(name);
    }
    /** Switch labels as javac encodes them; an EnumDesc is ConstantBootstraps.invoke(EnumDesc.of, ClassDesc.of(name), constant). */
    static Object label(ConstantDesc c,String where){
        if(c instanceof ClassDesc||c instanceof String||c instanceof Integer||c instanceof Enum.EnumDesc)return c;
        if(c instanceof DynamicConstantDesc<?> d&&d.bootstrapMethod().owner().equals(ClassDesc.of("java.lang.invoke.ConstantBootstraps"))
           &&d.bootstrapMethod().methodName().equals("primitiveClass")&&d.bootstrapArgs().length==0)return ClassDesc.ofDescriptor(d.constantName());
        if(invokes(c,"java.lang.Enum$EnumDesc","of",2)&&c instanceof DynamicConstantDesc<?> d&&d.bootstrapArgs()[2] instanceof String constant){
            ConstantDesc type=d.bootstrapArgs()[1];
            if(type instanceof ClassDesc t)return Enum.EnumDesc.of(t,constant);
            if(type instanceof DynamicConstantDesc<?> t&&t.bootstrapArgs()[t.bootstrapArgs().length-1] instanceof String n){
                if(invokes(t,"java.lang.constant.ClassDesc","of",1))return Enum.EnumDesc.of(ClassDesc.of(n),constant);
                if(invokes(t,"java.lang.constant.ClassDesc","ofDescriptor",1))return Enum.EnumDesc.of(ClassDesc.ofDescriptor(n),constant);
            }
        }
        throw new IllegalArgumentException("Unsupported switch label "+c+where+" (long/float/double/boolean labels are a preview feature)");
    }
    /** JDK unconditionalExactnessCheck for a primitive selector: same type, its wrapper, or an exact widening. */
    static boolean exact(ClassDesc from,ClassDesc to){
        if(from.equals(to)||to.equals(wrapper(from)))return true;
        String wider=switch(from.descriptorString()){case "B"->"SIJFD";case "S","C"->"IJFD";case "I"->"JD";case "F"->"D";default->"";};
        return to.isPrimitive()&&wider.contains(to.descriptorString());
    }
    /** JDK isNotValidPair: boolean and numeric primitive selectors never match each other's types. */
    static boolean invalidPair(ClassDesc selector,ClassDesc label){
        boolean bool=label.equals(CD_boolean)||label.equals(ClassDesc.of("java.lang.Boolean"));
        return selector.equals(CD_boolean)?!bool:selector.isPrimitive()&&bool;
    }
    /** SwitchBootstraps.typeSwitch/enumSwitch like the JDK 25 generated code: checkIndex(restart, n+1), -1 for null,
     * else the first label at index >= restart that matches, else n; equal adjacent labels are tested once. */
    static Inline switches(InvokeDynamicInstruction indy,String helper,String where){
        MethodTypeDesc type=indy.typeSymbol();boolean enumSwitch=indy.bootstrapMethod().methodName().equals("enumSwitch");
        if(type.parameterCount()!=2||!type.returnType().equals(CD_int)||!type.parameterType(1).equals(CD_int)||enumSwitch&&type.parameterType(0).isPrimitive())
            throw new IllegalArgumentException("Unsupported switch call site type "+type+where);
        ClassDesc selector=type.parameterType(0);List<Object> labels=new ArrayList<>();
        for(ConstantDesc c:indy.bootstrapArgs()){
            Object l=label(c,where);
            if(enumSwitch){if(l instanceof String s)l=Enum.EnumDesc.of(selector,s);else if(!selector.equals(l))throw new IllegalArgumentException("Illegal enumSwitch label "+l+where);}
            // javac uses primitive selectors for nested record patterns; only exact (non-preview) primitive patterns are supported.
            else if(l instanceof ClassDesc t&&t.isPrimitive()&&!(selector.isPrimitive()&&(exact(selector,t)||invalidPair(selector,t))))
                throw new IllegalArgumentException("Primitive type pattern "+t.displayName()+" for "+selector.displayName()+where+" is a preview feature");
            labels.add(l);
        }
        // An all-constant enumSwitch tests null before the index (JDK mappedEnumSwitch).
        boolean nullFirst=enumSwitch&&!labels.isEmpty()&&labels.stream().allMatch(l->l instanceof Enum.EnumDesc);
        int n=labels.size(),restart=slots(selector),target=selector.isPrimitive()?restart+1:0;
        return new Inline(helper,type,code->{
            Label dflt=code.newLabel(),present=code.newLabel();Label[] cases=new Label[n],next=new Label[n];
            Runnable check=()->code.iload(restart).loadConstant(n+1).invokestatic(OBJECTS,"checkIndex",MethodTypeDesc.of(CD_int,CD_int,CD_int)).pop();
            if(!nullFirst)check.run();
            // The JDK boxes a primitive selector before testing labels against it.
            if(selector.isPrimitive())code.loadLocal(kind(selector),0).invokestatic(wrapper(selector),"valueOf",MethodTypeDesc.of(wrapper(selector),selector)).astore(target);
            code.aload(target).ifnonnull(present).iconst_m1().ireturn().labelBinding(present);
            if(nullFirst)check.run();
            if(n==0){code.iconst_0().ireturn();return;}
            List<SwitchCase> table=new ArrayList<>();for(int i=0;i<n;i++)table.add(SwitchCase.of(i,cases[i]=code.newLabel()));
            for(int i=n-1;i>=0;i--)next[i]=i==n-1?dflt:labels.get(i+1).equals(labels.get(i))?next[i+1]:cases[i+1];
            code.iload(restart).tableswitch(0,n-1,dflt,table);
            for(int i=0;i<n;i++){
                code.labelBinding(cases[i]);Label fail=next[i];
                switch(labels.get(i)){
                    case ClassDesc t when selector.isPrimitive()&&invalidPair(selector,t)->code.goto_(fail);
                    case ClassDesc t->{if(!(t.equals(selector)||selector.isPrimitive()&&exact(selector,t)))code.aload(target).instanceOf(t).ifeq(fail);}
                    case String s->code.ldc(s).aload(target).invokevirtual(CD_String,"equals",MethodTypeDesc.of(CD_boolean,CD_Object)).ifeq(fail);
                    case Integer k->{
                        Label character=code.newLabel(),compare=code.newLabel();
                        code.aload(target).instanceOf(CD_Number).ifeq(character).aload(target).checkcast(CD_Number).invokevirtual(CD_Number,"intValue",MethodTypeDesc.of(CD_int)).goto_(compare);
                        code.labelBinding(character).aload(target).instanceOf(CD_Character).ifeq(fail).aload(target).checkcast(CD_Character).invokevirtual(CD_Character,"charValue",MethodTypeDesc.of(CD_char));
                        code.labelBinding(compare).loadConstant(k).if_icmpne(fail);
                    }
                    case Enum.EnumDesc<?> e->{
                        // Same constant <=> same enum class and name; non-enum values never resolve the label's class.
                        code.aload(target).instanceOf(CD_Enum).ifeq(fail).aload(target).instanceOf(e.constantType()).ifeq(fail);
                        code.ldc(e.constantName()).aload(target).checkcast(CD_Enum).invokevirtual(CD_Enum,"name",MethodTypeDesc.of(CD_String))
                            .invokevirtual(CD_String,"equals",MethodTypeDesc.of(CD_boolean,CD_Object)).ifeq(fail);
                    }
                    default->throw new IllegalArgumentException("Unsupported switch label "+labels.get(i)+where);
                }
                code.loadConstant(i).ireturn();
            }
            code.labelBinding(dflt).loadConstant(n).ireturn();
        });
    }
    static Lambda parse(ClassModel model,InvokeDynamicInstruction instruction,int ordinal){
        var bootstrap=instruction.bootstrapMethod();
        List<ConstantDesc> args=instruction.bootstrapArgs();
        MethodTypeDesc sam=(MethodTypeDesc)args.get(0),instantiated=(MethodTypeDesc)args.get(2);
        DirectMethodHandleDesc impl=(DirectMethodHandleDesc)args.get(1);
        ClassDesc owner=model.thisClass().asSymbol(),host=model.findAttribute(Attributes.nestHost()).map(a->a.nestHost().asSymbol()).orElse(owner);
        ClassDesc generated=ClassDesc.ofDescriptor("L"+internal(owner)+"$$JBV$Lambda$"+ordinal+";");
        if(models.containsKey(internal(generated)))throw new IllegalArgumentException("Generated class collision: "+generated);
        List<ClassDesc> interfaces=new ArrayList<>();interfaces.add(instruction.typeSymbol().returnType());
        List<MethodTypeDesc> bridges=new ArrayList<>();bridges.add(sam);
        if(bootstrap.methodName().equals("altMetafactory")){
            int flags=(Integer)args.get(3),at=4;
            if((flags&~7)!=0)throw new IllegalArgumentException("Unknown altMetafactory flags: "+flags);
            if((flags&1)!=0)interfaces.add(ClassDesc.of("java.io.Serializable"));
            if((flags&2)!=0){int n=(Integer)args.get(at++);while(n-->0)interfaces.add((ClassDesc)args.get(at++));}
            if((flags&4)!=0){int n=(Integer)args.get(at++);while(n-->0)bridges.add((MethodTypeDesc)args.get(at++));}
            if(at!=args.size())throw new IllegalArgumentException("Unexpected altMetafactory arguments");
        }
        if(!models.containsKey(internal(host)))throw new IllegalArgumentException("Nest host is missing from input: "+internal(host));
        nests.computeIfAbsent(internal(host),k->new ArrayList<>()).add(generated);
        String special=impl.refKind()==7?"$jbv$lambda$special$"+ordinal:null;
        if(special!=null&&model.methods().stream().anyMatch(m->m.methodName().equalsString(special)))throw new IllegalArgumentException("Bridge name collision: "+special);
        return new Lambda(owner,generated,host,instruction.name().stringValue(),instruction.typeSymbol(),sam,instantiated,impl,
            List.copyOf(new LinkedHashSet<>(interfaces)),List.copyOf(new LinkedHashSet<>(bridges)),special);
    }
    static ClassDesc wrapper(ClassDesc primitive){return ClassDesc.of("java.lang."+switch(primitive.descriptorString()){
        case "Z"->"Boolean";case "B"->"Byte";case "C"->"Character";case "S"->"Short";case "I"->"Integer";
        case "J"->"Long";case "F"->"Float";case "D"->"Double";default->throw new IllegalArgumentException("Not a value type: "+primitive);});}
    static String primitiveName(ClassDesc d){return switch(d.descriptorString()){
        case "Z"->"boolean";case "B"->"byte";case "C"->"char";case "S"->"short";case "I"->"int";case "J"->"long";case "F"->"float";case "D"->"double";default->throw new IllegalArgumentException();};}
    static void adapt(CodeBuilder code,ClassDesc from,ClassDesc to){
        if(from.equals(to))return;
        if(to.equals(CD_void)){if(!from.equals(CD_void)){if(slots(from)==2)code.pop2();else code.pop();}return;}
        if(from.equals(CD_void))throw new IllegalArgumentException("Cannot turn void into "+to);
        if(from.isPrimitive()&&to.isPrimitive()){
            TypeKind a=kind(from),b=kind(to);if(a!=b)code.conversion(a,b);return;
        }
        if(from.isPrimitive()){
            ClassDesc box=wrapper(from);code.invokestatic(box,"valueOf",MethodTypeDesc.of(box,from));
            if(!to.equals(CD_Object)&&!to.equals(box))code.checkcast(to);
        }else if(to.isPrimitive()){
            ClassDesc primitive=to;
            // Unbox the declared wrapper first; then widen its primitive value.
            for(ClassDesc p:List.of(CD_boolean,CD_byte,CD_char,CD_short,CD_int,CD_long,CD_float,CD_double))if(from.equals(wrapper(p)))primitive=p;
            ClassDesc box=wrapper(primitive);if(!from.equals(box))code.checkcast(box);
            code.invokevirtual(box,primitiveName(primitive)+"Value",MethodTypeDesc.of(primitive));adapt(code,primitive,to);
        }else if(!to.equals(CD_Object))code.checkcast(to);
    }
    static MethodTypeDesc bridgeType(Lambda p){return p.impl.invocationType().changeParameterType(0,p.owner);}
    static void implementationCall(CodeBuilder code,Lambda p){
        var impl=p.impl;var lookup=MethodTypeDesc.ofDescriptor(impl.lookupDescriptor());
        if(p.specialBridge!=null){code.invokestatic(p.owner,p.specialBridge,bridgeType(p),models.get(internal(p.owner)).flags().has(java.lang.reflect.AccessFlag.INTERFACE));return;}
        switch(impl.refKind()){
            case 6->code.invokestatic(impl.owner(),impl.methodName(),lookup,impl.isOwnerInterface());
            case 5->code.invokevirtual(impl.owner(),impl.methodName(),lookup);
            case 9->code.invokeinterface(impl.owner(),impl.methodName(),lookup);
            case 8->code.invokespecial(impl.owner(),"<init>",lookup,false);
            default->throw new IllegalArgumentException("Unsupported lambda implementation handle: "+impl);
        }
    }
    static byte[] generate(Lambda p){
        ClassDesc[] captures=p.factory.parameterArray();MethodTypeDesc ctor=MethodTypeDesc.of(CD_void,captures);
        return cf.build(p.generated,b->{
            b.withVersion(69,0).withFlags(ACC_FINAL|ACC_SUPER|ACC_SYNTHETIC).withSuperclass(CD_Object).withInterfaceSymbols(p.interfaces).with(NestHostAttribute.of(p.host));
            for(int i=0;i<captures.length;i++)b.withField("capture"+i,captures[i],ACC_PRIVATE|ACC_FINAL);
            b.withMethodBody("<init>",ctor,ACC_PRIVATE,code->{
                code.aload(0).invokespecial(CD_Object,"<init>",MethodTypeDesc.of(CD_void),false);int local=1;
                for(int i=0;i<captures.length;i++){code.aload(0).loadLocal(kind(captures[i]),local).putfield(p.generated,"capture"+i,captures[i]);local+=slots(captures[i]);}code.return_();
            });
            b.withMethodBody("create",p.factory,ACC_PUBLIC|ACC_STATIC,code->{
                code.new_(p.generated).dup();int local=0;for(ClassDesc capture:captures){code.loadLocal(kind(capture),local);local+=slots(capture);}code.invokespecial(p.generated,"<init>",ctor,false).areturn();
            });
            for(MethodTypeDesc sam:p.bridges)b.withMethodBody(p.name,sam,ACC_PUBLIC|(sam.equals(p.sam)?0:ACC_BRIDGE|ACC_SYNTHETIC),code->{
                MethodTypeDesc target=p.specialBridge==null?p.impl.invocationType():bridgeType(p);
                if(target.parameterCount()!=captures.length+p.instantiated.parameterCount())throw new IllegalArgumentException("Incompatible lambda arity: "+p.generated);
                if(p.impl.refKind()==8)code.new_(p.impl.owner()).dup();
                int param=0,local=1;
                for(int i=0;i<captures.length;i++){code.aload(0).getfield(p.generated,"capture"+i,captures[i]);adapt(code,captures[i],target.parameterType(param++));}
                for(int i=0;i<sam.parameterCount();i++){
                    code.loadLocal(kind(sam.parameterType(i)),local);local+=slots(sam.parameterType(i));
                    adapt(code,sam.parameterType(i),p.instantiated.parameterType(i));adapt(code,p.instantiated.parameterType(i),target.parameterType(param++));
                }
                implementationCall(code,p);adapt(code,target.returnType(),p.instantiated.returnType());adapt(code,p.instantiated.returnType(),sam.returnType());code.return_(kind(sam.returnType()));
            });
        });
    }
    public static void main(String[] args)throws Exception{
        try{lower(args);}catch(IllegalArgumentException e){System.err.println("LowerLambdas: "+e.getMessage());System.exit(1);}
    }
    static void lower(String[] args)throws Exception{
        if(args.length!=2)throw new IllegalArgumentException("Usage: LowerLambdas.java INPUT_DIRECTORY OUTPUT_DIRECTORY");
        Path input=Path.of(args[0]).toAbsolutePath().normalize(),destination=Path.of(args[1]).toAbsolutePath().normalize();
        if(input.equals(destination)||destination.startsWith(input))throw new IllegalArgumentException("Output must be separate from input");
        try(URLClassLoader loader=new URLClassLoader(new URL[]{input.toUri().toURL()})){
            cf=ClassFile.of(ConstantPoolSharingOption.NEW_POOL,
                ClassHierarchyResolverOption.of(ClassHierarchyResolver.ofResourceParsing(loader)));
            List<Path> files;try(var stream=Files.walk(input)){files=stream.filter(Files::isRegularFile).sorted().toList();}
            for(Path file:files)if(file.toString().endsWith(".class")){ClassModel model=cf.parse(file);models.put(model.thisClass().asInternalName(),model);}
            Map<String,Map<Integer,Object>> sites=new HashMap<>();int inlined=0;
            for(var entry:models.entrySet()){
                Map<Integer,Object> found=new LinkedHashMap<>();List<Lambda> lambdas=new ArrayList<>();int inlines=0;
                for(MethodModel method:entry.getValue().methods())if(method.code().isPresent())for(CodeElement element:method.code().get())
                    if(element instanceof InvokeDynamicInstruction indy&&!found.containsKey(indy.invokedynamic().index())){
                        Object p=plan(entry.getValue(),indy,lambdas.size(),inlines);found.put(indy.invokedynamic().index(),p);
                        if(p instanceof Lambda l)lambdas.add(l);else inlines++;
                    }
                plans.put(entry.getKey(),lambdas);sites.put(entry.getKey(),found);inlined+=inlines;
            }
            for(var entry:models.entrySet()){
                List<Lambda> lambdas=plans.get(entry.getKey());Map<Integer,Object> byIndex=sites.get(entry.getKey());
                ClassDesc self=entry.getValue().thisClass().asSymbol();boolean isInterface=entry.getValue().flags().has(java.lang.reflect.AccessFlag.INTERFACE);
                CodeTransform transform=(code,element)->{
                    if(!(element instanceof InvokeDynamicInstruction indy))code.with(element);
                    else if(byIndex.get(indy.invokedynamic().index()) instanceof Lambda p)code.invokestatic(p.generated,"create",p.factory);
                    else{Inline p=(Inline)byIndex.get(indy.invokedynamic().index());code.invokestatic(self,p.name,p.type,isInterface);}
                };
                ClassTransform classTransform=(b,element)->{
                    if(element instanceof NestMembersAttribute&&nests.containsKey(entry.getKey()))return;
                    if(element instanceof MethodModel method)b.transformMethod(method,MethodTransform.transformingCode(transform));else b.with(element);
                };
                ClassTransform tail=ClassTransform.endHandler(b->{
                    if(nests.containsKey(entry.getKey())){
                        List<ClassDesc> members=new ArrayList<>();entry.getValue().findAttribute(Attributes.nestMembers()).ifPresent(a->a.nestMembers().forEach(c->members.add(c.asSymbol())));members.addAll(nests.get(entry.getKey()));b.with(NestMembersAttribute.ofSymbols(members));
                    }
                    for(Lambda p:lambdas)if(p.specialBridge!=null)b.withMethodBody(p.specialBridge,bridgeType(p),ACC_PRIVATE|ACC_STATIC|ACC_SYNTHETIC,code->{
                        int local=0;for(ClassDesc type:bridgeType(p).parameterArray()){code.loadLocal(kind(type),local);local+=slots(type);}
                        code.invokespecial(p.impl.owner(),p.impl.methodName(),MethodTypeDesc.ofDescriptor(p.impl.lookupDescriptor()),p.impl.isOwnerInterface()).return_(kind(p.impl.invocationType().returnType()));
                    });
                    for(Object p:byIndex.values())if(p instanceof Inline i)b.withMethodBody(i.name,i.type,ACC_PRIVATE|ACC_STATIC|ACC_SYNTHETIC,i.body);
                });
                output.put(entry.getKey()+".class",cf.transformClass(entry.getValue(),classTransform.andThen(tail)));
                for(Lambda p:lambdas)output.put(internal(p.generated)+".class",generate(p));
            }
            // Build everything before publishing files, so unsupported sites leave no partial output.
            for(Path file:files)if(!file.toString().endsWith(".class"))output.put(input.relativize(file).toString(),Files.readAllBytes(file));
            for(var entry:output.entrySet()){Path path=destination.resolve(entry.getKey());Files.createDirectories(path.getParent());Files.write(path,entry.getValue());}
            System.out.println("Lowered "+plans.values().stream().mapToInt(List::size).sum()+" lambda sites and "+inlined+" record/switch sites to ordinary Java 25 bytecode.");
        }
    }
}
