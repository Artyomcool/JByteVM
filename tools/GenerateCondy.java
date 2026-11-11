import java.lang.classfile.*;
import java.lang.constant.*;
import java.nio.file.*;
import java.util.*;
import static java.lang.constant.ConstantDescs.*;
public class GenerateCondy {
    static final ClassDesc OWNER=ClassDesc.of("CondyValues"),LOOKUP=ClassDesc.of("java.lang.invoke.MethodHandles$Lookup"),CB=ClassDesc.of("java.lang.invoke.ConstantBootstraps");
    static DirectMethodHandleDesc bsm(ClassDesc owner,String name,ClassDesc result,ClassDesc... tail){ClassDesc[] args=new ClassDesc[tail.length+3];args[0]=LOOKUP;args[1]=CD_String;args[2]=CD_Class;System.arraycopy(tail,0,args,3,tail.length);return MethodHandleDesc.ofMethod(DirectMethodHandleDesc.Kind.STATIC,owner,name,MethodTypeDesc.of(result,args));}
    static DynamicConstantDesc<?> constant(String name,ClassDesc type,DirectMethodHandleDesc bsm,ConstantDesc... args){return DynamicConstantDesc.ofNamed(bsm,name,type,args);}
    public static void main(String[] args)throws Exception{
        Map<String,DynamicConstantDesc<?>> constants=new HashMap<>();
        var integer=constant("integer",CD_int,bsm(OWNER,"integer",CD_int,CD_int,CD_int),17,25);
        constants.put("integer",integer);
        constants.put("wide",constant("wide",CD_long,bsm(OWNER,"wide",CD_long,CD_long),0x123456789abcdef0L));
        constants.put("text",constant("text",CD_String,bsm(OWNER,"text",CD_Object,CD_Object.arrayType()),17,"hello"));
        constants.put("nil",constant("nil",CD_Object,bsm(CB,"nullConstant",CD_Object)));
        constants.put("primitive",constant("I",CD_Class,bsm(CB,"primitiveClass",CD_Class)));
        constants.put("fixed",constant("FIELD",CD_int,bsm(CB,"getStaticFinal",CD_Object,CD_Class),OWNER));
        constants.put("nested",constant("nested",CD_int,bsm(OWNER,"integer",CD_int,CD_int,CD_int),integer,1));
        constants.put("handle",constant("handle",CD_int,bsm(OWNER,"handle",CD_Object,CD_MethodHandle,CD_MethodType),MethodHandleDesc.ofMethod(DirectMethodHandleDesc.Kind.STATIC,OWNER,"target",MethodTypeDesc.of(CD_int,CD_int)),MethodTypeDesc.of(CD_int,CD_int)));
        constants.put("failure",constant("failure",CD_int,bsm(OWNER,"failure",CD_Object)));
        constants.put("badType",constant("badType",CD_int,bsm(OWNER,"badType",CD_Object)));
        constants.put("recurse",constant("recurse",CD_int,bsm(OWNER,"recurse",CD_Object)));
        constants.put("choice",constant("B",ClassDesc.of("CondyValues$Choice"),bsm(CB,"enumConstant",ClassDesc.of("java.lang.Enum"))));
        Path path=Path.of(args[0],"Condy.class");ClassFile cf=ClassFile.of();ClassModel model=cf.parse(path);
        byte[] bytes=cf.transformClass(model,(builder,element)->{
            if(element instanceof MethodModel m && constants.containsKey(m.methodName().stringValue())){
                DynamicConstantDesc<?> value=constants.get(m.methodName().stringValue());
                builder.withMethodBody(m.methodName(),m.methodType(),m.flags().flagsMask(),code->code.ldc(value).return_(TypeKind.fromDescriptor(value.constantType().descriptorString())));
            }else builder.with(element);
        });
        Files.write(path,bytes);
        ClassDesc extra=ClassDesc.of("CondyExtra"),carrier=ClassDesc.of("CondyExtra$Carrier");
        for(ClassDesc owner:List.of(extra,carrier)){
            Path file=Path.of(args[0],owner.displayName()+".class");
            ClassModel input=cf.parse(file);
            Files.write(file,cf.transformClass(input,(builder,element)->{
                if(element instanceof MethodModel m && (owner.equals(carrier)&&m.methodName().equalsString("nil") || owner.equals(extra)&&(m.methodName().equalsString("value")||m.methodName().equalsString("nativeValue")))){
                    String name=m.methodName().stringValue();ClassDesc type=owner.equals(carrier)?CD_Object:name.equals("value")?CD_long:CD_int;
                    String bootstrap=owner.equals(carrier)?"nil":name.equals("value")?"number":"nativeBootstrap";
                    var value=constant(name,type,bsm(extra,bootstrap,type));
                    builder.withMethodBody(m.methodName(),m.methodType(),m.flags().flagsMask(),code->code.ldc(value).return_(TypeKind.fromDescriptor(type.descriptorString())));
                }else builder.with(element);
            }));
        }
    }
}
