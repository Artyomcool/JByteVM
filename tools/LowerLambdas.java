import java.lang.classfile.*;
import java.lang.classfile.attribute.*;
import java.lang.classfile.instruction.*;
import java.lang.constant.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import static java.lang.constant.ConstantDescs.*;
import static java.lang.classfile.ClassFile.*;

/** Build-time LambdaMetafactory lowering; never runs the application's code. */
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
                  List<ClassDesc> interfaces,List<MethodTypeDesc> bridges,int cpIndex,String specialBridge) {}
    static Lambda parse(ClassModel model,InvokeDynamicInstruction instruction,int ordinal){
        var bootstrap=instruction.bootstrapMethod();
        if(!bootstrap.owner().equals(ClassDesc.of("java.lang.invoke.LambdaMetafactory"))||
           !(bootstrap.methodName().equals("metafactory")||bootstrap.methodName().equals("altMetafactory")))
            throw new IllegalArgumentException("Unsupported invokedynamic bootstrap in "+model.thisClass().asInternalName()+": "+bootstrap+"; compile string concatenation with -XDstringConcat=inline");
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
            List.copyOf(new LinkedHashSet<>(interfaces)),List.copyOf(new LinkedHashSet<>(bridges)),instruction.invokedynamic().index(),special);
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
        if(args.length!=2)throw new IllegalArgumentException("Usage: LowerLambdas.java INPUT_DIRECTORY OUTPUT_DIRECTORY");
        Path input=Path.of(args[0]).toAbsolutePath().normalize(),destination=Path.of(args[1]).toAbsolutePath().normalize();
        if(input.equals(destination)||destination.startsWith(input))throw new IllegalArgumentException("Output must be separate from input");
        try(URLClassLoader loader=new URLClassLoader(new URL[]{input.toUri().toURL()})){
            cf=ClassFile.of(ConstantPoolSharingOption.NEW_POOL,
                ClassHierarchyResolverOption.of(ClassHierarchyResolver.ofResourceParsing(loader)));
            List<Path> files;try(var stream=Files.walk(input)){files=stream.filter(Files::isRegularFile).sorted().toList();}
            for(Path file:files)if(file.toString().endsWith(".class")){ClassModel model=cf.parse(file);models.put(model.thisClass().asInternalName(),model);}
            for(var entry:models.entrySet()){
                LinkedHashMap<Integer,Lambda> found=new LinkedHashMap<>();
                for(MethodModel method:entry.getValue().methods())if(method.code().isPresent())for(CodeElement element:method.code().get())
                    if(element instanceof InvokeDynamicInstruction indy&&!found.containsKey(indy.invokedynamic().index()))found.put(indy.invokedynamic().index(),parse(entry.getValue(),indy,found.size()));
                plans.put(entry.getKey(),new ArrayList<>(found.values()));
            }
            for(var entry:models.entrySet()){
                List<Lambda> lambdas=plans.get(entry.getKey());Map<Integer,Lambda> byIndex=new HashMap<>();for(Lambda p:lambdas)byIndex.put(p.cpIndex,p);
                CodeTransform transform=(code,element)->{if(element instanceof InvokeDynamicInstruction indy){Lambda p=byIndex.get(indy.invokedynamic().index());code.invokestatic(p.generated,"create",p.factory);}else code.with(element);};
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
                });
                output.put(entry.getKey()+".class",cf.transformClass(entry.getValue(),classTransform.andThen(tail)));
                for(Lambda p:lambdas)output.put(internal(p.generated)+".class",generate(p));
            }
            // Build everything before publishing files, so unsupported sites leave no partial output.
            for(Path file:files)if(!file.toString().endsWith(".class"))output.put(input.relativize(file).toString(),Files.readAllBytes(file));
            for(var entry:output.entrySet()){Path path=destination.resolve(entry.getKey());Files.createDirectories(path.getParent());Files.write(path,entry.getValue());}
            System.out.println("Lowered "+plans.values().stream().mapToInt(List::size).sum()+" lambda sites; generated ordinary Java 25 classes.");
        }
    }
}
