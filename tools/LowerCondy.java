import java.lang.classfile.*;
import java.lang.classfile.attribute.*;
import java.lang.classfile.constantpool.*;
import java.lang.classfile.instruction.*;
import java.lang.constant.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import static java.lang.constant.ConstantDescs.*;
import static java.lang.classfile.ClassFile.*;

/** Replaces ldc condy with ordinary, lazily cached interpreter bytecode.
 * Only class resources are parsed; no application/bootstrap code is executed. */
public class LowerCondy {
    static final ClassDesc LOOKUP=ClassDesc.of("java.lang.invoke.MethodHandles$Lookup"),
        HANDLES=ClassDesc.of("java.lang.invoke.MethodHandles"),ERROR=ClassDesc.of("java.lang.Error"),
        BME=ClassDesc.of("java.lang.BootstrapMethodError");
    static ClassFile cf;
    record Plan(ClassModel model,ClassDesc owner,ClassDesc holder,ClassDesc host,List<ConstantDynamicEntry> constants) {}
    static String internal(ClassDesc c){String d=c.descriptorString();return d.substring(1,d.length()-1);}
    static String method(ConstantDynamicEntry c){return "$jbv$condy$"+c.index();}
    static TypeKind kind(ClassDesc c){return TypeKind.fromDescriptor(c.descriptorString());}
    static void collect(ConstantDynamicEntry entry,Map<Integer,ConstantDynamicEntry> found){
        if(found.putIfAbsent(entry.index(),entry)!=null)return;
        for(LoadableConstantEntry argument:entry.bootstrap().arguments())if(argument instanceof ConstantDynamicEntry nested)collect(nested,found);
    }
    static void classLiteral(CodeBuilder b,ClassDesc type){
        if(type.isPrimitive()){
            String wrapper=switch(type.descriptorString()){case "Z"->"Boolean";case "B"->"Byte";case "C"->"Character";case "S"->"Short";case "I"->"Integer";case "J"->"Long";case "F"->"Float";case "D"->"Double";default->throw new IllegalArgumentException("Invalid condy type: "+type);};
            b.getstatic(ClassDesc.of("java.lang."+wrapper),"TYPE",CD_Class);
        }else b.ldc(type);
    }
    static ClassDesc emit(CodeBuilder b,LoadableConstantEntry value,Plan p){
        if(value instanceof ConstantDynamicEntry d){b.invokestatic(p.holder,method(d),MethodTypeDesc.of(d.typeSymbol()));return d.typeSymbol();}
        ConstantDesc c=value.constantValue();b.ldc(c);
        if(c instanceof Integer)return CD_int;if(c instanceof Long)return CD_long;if(c instanceof Float)return CD_float;if(c instanceof Double)return CD_double;
        if(c instanceof String)return CD_String;if(c instanceof ClassDesc)return CD_Class;if(c instanceof MethodTypeDesc)return CD_MethodType;
        if(c instanceof MethodHandleDesc)return CD_MethodHandle;
        throw new IllegalArgumentException("Unsupported bootstrap constant: "+c);
    }
    static void helper(ClassBuilder b,Plan p,ConstantDynamicEntry d){
        b.withMethodBody(method(d),MethodTypeDesc.of(d.typeSymbol()),ACC_PRIVATE|ACC_STATIC|ACC_SYNTHETIC,code->{
            code.ldc(d.bootstrap().bootstrapMethod().asSymbol());
            code.invokestatic(HANDLES,"lookup",MethodTypeDesc.of(LOOKUP));
            code.ldc(d.nameAndType().name().stringValue());classLiteral(code,d.typeSymbol());
            List<ClassDesc> arguments=new ArrayList<>(List.of(LOOKUP,CD_String,CD_Class));
            for(LoadableConstantEntry argument:d.bootstrap().arguments())arguments.add(emit(code,argument,p));
            // Signature-polymorphic invocation performs the BSM's boxing,
            // widening, varargs collection and result adaptation at run time.
            code.invokevirtual(CD_MethodHandle,"invoke",MethodTypeDesc.of(d.typeSymbol(),arguments.toArray(ClassDesc[]::new)));
            code.return_(kind(d.typeSymbol()));
        });
    }
    static byte[] holder(Plan p){return cf.build(p.holder,b->{
        b.withVersion(69,0).withFlags(ACC_FINAL|ACC_SUPER|ACC_SYNTHETIC).withSuperclass(CD_Object).with(NestHostAttribute.of(p.host));
        for(ConstantDynamicEntry d:p.constants){
            String name=method(d);ClassDesc type=d.typeSymbol();
            b.withField(name+"$value",type,ACC_PRIVATE|ACC_STATIC|ACC_SYNTHETIC);
            b.withField(name+"$ready",CD_boolean,ACC_PRIVATE|ACC_STATIC|ACC_SYNTHETIC);
            b.withField(name+"$error",CD_Throwable,ACC_PRIVATE|ACC_STATIC|ACC_SYNTHETIC);
            b.withMethodBody(name,MethodTypeDesc.of(type),ACC_STATIC|ACC_SYNCHRONIZED|ACC_SYNTHETIC,code->{
                Label value=code.newLabel(),empty=code.newLabel(),begin=code.newLabel(),end=code.newLabel(),handler=code.newLabel(),save=code.newLabel();
                code.getstatic(p.holder,name+"$ready",CD_boolean).ifne(value);
                code.getstatic(p.holder,name+"$error",CD_Throwable).dup().ifnull(empty).athrow();
                code.labelBinding(empty).pop().labelBinding(begin);
                code.invokestatic(p.owner,name,MethodTypeDesc.of(type),p.model.flags().has(java.lang.reflect.AccessFlag.INTERFACE));
                code.putstatic(p.holder,name+"$value",type).iconst_1().putstatic(p.holder,name+"$ready",CD_boolean);
                code.labelBinding(end).labelBinding(value).getstatic(p.holder,name+"$value",type).return_(kind(type));
                code.labelBinding(handler).astore(0).aload(0).instanceOf(ERROR).ifne(save);
                code.new_(BME).dup().aload(0).invokespecial(BME,"<init>",MethodTypeDesc.of(CD_void,CD_Throwable),false).astore(0);
                code.labelBinding(save).aload(0).dup().putstatic(p.holder,name+"$error",CD_Throwable).athrow();
                code.exceptionCatch(begin,end,handler,CD_Throwable);
            });
        }
    });}
    public static void main(String[] args)throws Exception{
        if(args.length!=2)throw new IllegalArgumentException("Usage: LowerCondy.java INPUT_DIRECTORY OUTPUT_DIRECTORY");
        Path input=Path.of(args[0]).toAbsolutePath().normalize(),destination=Path.of(args[1]).toAbsolutePath().normalize();
        if(input.equals(destination)||destination.startsWith(input))throw new IllegalArgumentException("Output must be separate from input");
        Map<String,ClassModel> models=new LinkedHashMap<>();Map<String,Plan> plans=new LinkedHashMap<>();Map<String,List<ClassDesc>> nests=new HashMap<>();Map<String,byte[]> output=new LinkedHashMap<>();
        try(URLClassLoader loader=new URLClassLoader(new URL[]{input.toUri().toURL()})){
            cf=ClassFile.of(ConstantPoolSharingOption.NEW_POOL,ClassHierarchyResolverOption.of(ClassHierarchyResolver.ofResourceParsing(loader)));
            List<Path> files;try(var stream=Files.walk(input)){files=stream.filter(Files::isRegularFile).sorted().toList();}
            for(Path file:files)if(file.toString().endsWith(".class")){ClassModel m=cf.parse(file);models.put(m.thisClass().asInternalName(),m);}
            for(var entry:models.entrySet()){
                ClassModel m=entry.getValue();Map<Integer,ConstantDynamicEntry> found=new LinkedHashMap<>();
                for(MethodModel method:m.methods())if(method.code().isPresent())for(CodeElement e:method.code().get())
                    if(e instanceof ConstantInstruction.LoadConstantInstruction load&&load.constantEntry() instanceof ConstantDynamicEntry d)collect(d,found);
                List<ConstantDynamicEntry> constants=new ArrayList<>(found.values());
                if(constants.isEmpty())continue;
                ClassDesc owner=m.thisClass().asSymbol(),host=m.findAttribute(Attributes.nestHost()).map(a->a.nestHost().asSymbol()).orElse(owner);
                ClassDesc holder=ClassDesc.ofDescriptor("L"+entry.getKey()+"$$JBV$Condy;");
                if(models.containsKey(internal(holder)))throw new IllegalArgumentException("Generated class collision: "+holder);
                if(!models.containsKey(internal(host)))throw new IllegalArgumentException("Nest host is missing from input: "+host);
                for(var d:constants){
                    if(d.typeSymbol().equals(CD_void))throw new IllegalArgumentException("void condy in "+owner);
                    if(m.methods().stream().anyMatch(method->method.methodName().equalsString(method(d))))throw new IllegalArgumentException("Generated member collision: "+method(d));
                    if(d.bootstrap().bootstrapMethod().kind()!=6&&d.bootstrap().bootstrapMethod().kind()!=8)throw new IllegalArgumentException("Unsupported bootstrap handle kind in "+owner);
                }
                plans.put(entry.getKey(),new Plan(m,owner,holder,host,List.copyOf(constants)));
                nests.computeIfAbsent(internal(host),key->new ArrayList<>()).add(holder);
            }
            for(var entry:models.entrySet()){
                Plan p=plans.get(entry.getKey());
                ClassTransform transform=(b,e)->{
                    if(e instanceof NestMembersAttribute&&nests.containsKey(entry.getKey()))return;
                    if(p!=null&&e instanceof MethodModel m)b.transformMethod(m,MethodTransform.transformingCode((code,instruction)->{
                        if(instruction instanceof ConstantInstruction.LoadConstantInstruction load&&load.constantEntry() instanceof ConstantDynamicEntry d)code.invokestatic(p.holder,method(d),MethodTypeDesc.of(d.typeSymbol()));
                        else code.with(instruction);
                    }));else b.with(e);
                };
                ClassTransform tail=ClassTransform.endHandler(b->{
                    if(nests.containsKey(entry.getKey())){
                        List<ClassDesc> members=new ArrayList<>();entry.getValue().findAttribute(Attributes.nestMembers()).ifPresent(a->a.nestMembers().forEach(c->members.add(c.asSymbol())));members.addAll(nests.get(entry.getKey()));b.with(NestMembersAttribute.ofSymbols(members));
                    }
                    if(p!=null)for(var d:p.constants)helper(b,p,d);
                });
                output.put(entry.getKey()+".class",cf.transformClass(entry.getValue(),transform.andThen(tail)));
                if(p!=null)output.put(internal(p.holder)+".class",holder(p));
            }
            for(Path file:files)if(!file.toString().endsWith(".class"))output.put(input.relativize(file).toString(),Files.readAllBytes(file));
            for(var entry:output.entrySet()){Path path=destination.resolve(entry.getKey());Files.createDirectories(path.getParent());Files.write(path,entry.getValue());}
            System.out.println("Lowered "+plans.values().stream().mapToInt(p->p.constants.size()).sum()+" dynamic constants to lazy ordinary bytecode.");
        }
    }
}
