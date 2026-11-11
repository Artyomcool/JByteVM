package jbv.runtime;
import java.lang.annotation.Annotation;
import java.lang.reflect.*;
import java.util.Arrays;
import java.util.Objects;
/** Generic signatures (JVMS 4.7.9.1) parsed on demand into java.lang.reflect.Type objects.
 * Raw signature strings come from the VM; nothing is cached, equal types compare equal. */
public final class Generics {
    private Generics() {}
    private static final Type[] NONE=new Type[0];
    private static final Type[] OBJECT={Object.class};

    /** Class.getGenericSuperclass(0) / getGenericInterfaces(1) / getTypeParameters(2) / getTypeName(3). */
    public static Object ofClass(Class<?> c,int what){
        if(what==3){if(!c.isArray())return c.getName();int n=0;while(c.isArray()){c=c.getComponentType();n++;}StringBuilder s=new StringBuilder(c.getName());while(n-->0)s.append("[]");return s.toString();}
        String sig=Reflection.classSignature(c);
        if(sig==null){if(what==0)return c.getSuperclass();if(what==1){Class<?>[] f=c.getInterfaces();Type[] r=new Type[f.length];System.arraycopy(f,0,r,0,f.length);return r;}return new TypeVariable[0];}
        Parser p=new Parser(sig,c);TypeVariable<?>[] params=p.typeParameters();
        if(what==2)return params;
        Type parent=p.type();
        if(what==0)return c.getSuperclass()==null?null:parent;
        java.util.ArrayList<Type> faces=new java.util.ArrayList<>();while(p.more())faces.add(p.type());
        return faces.toArray(new Type[faces.size()]);
    }
    /** Field.getGenericType(0), Method.getGenericReturnType(1), parameters(2), exceptions(3), type parameters(4). */
    public static Object member(AccessibleObject m,int what){
        String sig=(String)Reflection.info(m,5);
        if(m instanceof Field f)return sig==null?f.getType():new Parser(sig,f.getDeclaringClass()).type();
        Executable e=(Executable)m;
        if(sig==null){
            if(what==1)return ((Method)e).getReturnType();
            if(what==4)return new TypeVariable[0];
            Class<?>[] raw=what==2?e.getParameterTypes():e.getExceptionTypes();Type[] r=new Type[raw.length];System.arraycopy(raw,0,r,0,raw.length);return r;
        }
        Parser p=new Parser(sig,(GenericDeclaration)e);TypeVariable<?>[] params=p.typeParameters();
        if(what==4)return params;
        java.util.ArrayList<Type> args=new java.util.ArrayList<>();p.expect('(');while(!p.peek(')'))args.add(p.type());p.expect(')');
        Type result=p.peek('V')?p.skipVoid():p.type();
        if(what==1)return result;
        if(what==2)return args.toArray(new Type[args.size()]);
        java.util.ArrayList<Type> thrown=new java.util.ArrayList<>();while(p.more()){p.expect('^');thrown.add(p.type());}
        if(thrown.isEmpty()){Class<?>[] raw=e.getExceptionTypes();Type[] r=new Type[raw.length];System.arraycopy(raw,0,r,0,raw.length);return r;}
        return thrown.toArray(new Type[thrown.size()]);
    }
    static Class<?> load(String binary){
        try{return Class.forName(binary.replace('/','.'),false,null);}
        catch(ClassNotFoundException e){throw new TypeNotPresentException(binary.replace('/','.'),e);}
    }
    /** Nearest declaring scope for a type variable: the member, then its class, then outer classes. */
    static TypeVariable<?> lookup(String name,GenericDeclaration scope){
        GenericDeclaration first=scope;
        while(scope!=null){
            for(TypeVariable<?> v:scope.getTypeParameters())if(v.getName().equals(name))return v;
            if(scope instanceof Executable e)scope=e.getDeclaringClass();
            else{String n=((Class<?>)scope).getName();int cut=n.lastIndexOf('$');scope=null;if(cut>0)try{scope=Class.forName(n.substring(0,cut),false,null);}catch(ClassNotFoundException ignored){}}
        }
        return new Variable(name,first,null);
    }

    static final class Parser {
        final String s;final GenericDeclaration scope;int at;boolean skip;
        Parser(String s,GenericDeclaration scope){this.s=s;this.scope=scope;}
        boolean more(){return at<s.length();}
        boolean peek(char c){return at<s.length()&&s.charAt(at)==c;}
        void expect(char c){if(!peek(c))throw new MalformedParameterizedTypeException("Bad signature: "+s);at++;}
        Type skipVoid(){at++;return void.class;}
        String ident(String stops){int start=at;while(at<s.length()&&stops.indexOf(s.charAt(at))<0)at++;return s.substring(start,at);}
        TypeVariable<?>[] typeParameters(){
            if(!peek('<'))return new TypeVariable[0];
            at++;java.util.ArrayList<TypeVariable<?>> r=new java.util.ArrayList<>();
            while(!peek('>')){
                String name=ident(":");int start=at;
                // Bounds are only skipped here: resolving T in them would recurse into getTypeParameters.
                skip=true;while(peek(':')){at++;if(!peek(':')&&!peek('>'))type();}skip=false;
                r.add(new Variable(name,scope,s.substring(start,at)));
            }
            at++;return r.toArray(new TypeVariable[r.size()]);
        }
        Type type(){
            if(!more())throw new MalformedParameterizedTypeException("Bad signature: "+s);
            char c=s.charAt(at++);
            switch(c){
            case 'Z':return boolean.class;case 'B':return byte.class;case 'C':return char.class;case 'S':return short.class;
            case 'I':return int.class;case 'J':return long.class;case 'F':return float.class;case 'D':return double.class;
            case 'T':{String name=ident(";");at++;return skip?null:scope==null?new Variable(name,null,null):lookup(name,scope);}
            case '[':{Type t=type();return skip?null:t instanceof Class<?> k?Array.newInstance(k,0).getClass():new GenericArray(t);}
            case 'L':return classType();
            default:throw new MalformedParameterizedTypeException("Bad signature: "+s);
            }
        }
        Type classType(){
            StringBuilder binary=new StringBuilder(ident("<.;"));Type owner=null;Type current=null;
            while(true){
                Type[] args=null;
                if(peek('<')){at++;java.util.ArrayList<Type> list=new java.util.ArrayList<>();while(!peek('>'))list.add(argument());at++;args=list.toArray(new Type[list.size()]);}
                if(skip){if(peek('.')){at++;binary.append('$').append(ident("<.;"));continue;}expect(';');return null;}
                Class<?> raw=load(binary.toString());
                current=args==null&&owner==null?raw:new Parameterized(raw,args==null?NONE:args,owner!=null?owner:outer(raw));
                if(peek('.')){at++;owner=current;binary.append('$').append(ident("<.;"));continue;}
                expect(';');return current;
            }
        }
        Type argument(){
            if(peek('*')){at++;return new Wildcard(OBJECT,NONE);}
            if(peek('+')){at++;return new Wildcard(new Type[]{type()},NONE);}
            if(peek('-')){at++;return new Wildcard(OBJECT,new Type[]{type()});}
            return type();
        }
    }
    static Class<?> outer(Class<?> raw){String n=raw.getName();int cut=n.lastIndexOf('$');if(cut<0)return null;try{return Class.forName(n.substring(0,cut),false,null);}catch(ClassNotFoundException e){return null;}}
    static String names(Type[] types,String open,String close){
        StringBuilder s=new StringBuilder(open);
        for(int i=0;i<types.length;i++){if(i>0)s.append(", ");s.append(types[i].getTypeName());}
        return s.append(close).toString();
    }

    static final class Parameterized implements ParameterizedType {
        final Class<?> raw;final Type[] args;final Type owner;
        Parameterized(Class<?> raw,Type[] args,Type owner){this.raw=raw;this.args=args;this.owner=owner;}
        public Type[] getActualTypeArguments(){return args.clone();}
        public Type getRawType(){return raw;}
        public Type getOwnerType(){return owner;}
        public boolean equals(Object o){return o instanceof ParameterizedType p&&raw.equals(p.getRawType())&&Objects.equals(owner,p.getOwnerType())&&Arrays.equals(args,p.getActualTypeArguments());}
        public int hashCode(){return Arrays.hashCode(args)^Objects.hashCode(owner)^raw.hashCode();}
        public String toString(){
            StringBuilder s=new StringBuilder();
            if(owner instanceof Parameterized p)s.append(p.getTypeName()).append('$').append(raw.getName().substring(p.raw.getName().length()+1));
            else s.append(raw.getName());
            if(args.length>0)s.append(names(args,"<",">"));
            return s.toString();
        }
    }
    static final class Variable implements TypeVariable<GenericDeclaration> {
        final String name;final GenericDeclaration owner;final String bounds;
        Variable(String name,GenericDeclaration owner,String bounds){this.name=name;this.owner=owner;this.bounds=bounds;}
        public String getName(){return name;}
        public GenericDeclaration getGenericDeclaration(){return owner;}
        public Type[] getBounds(){
            if(bounds==null)return OBJECT.clone();
            Parser p=new Parser(bounds,owner);java.util.ArrayList<Type> r=new java.util.ArrayList<>();
            while(p.peek(':')){p.at++;if(p.more()&&!p.peek(':'))r.add(p.type());}
            return r.isEmpty()?OBJECT.clone():r.toArray(new Type[r.size()]);
        }
        public Annotation[] getDeclaredAnnotations(){return new Annotation[0];}
        public Annotation[] getAnnotations(){return new Annotation[0];}
        public boolean equals(Object o){return o instanceof TypeVariable<?> v&&name.equals(v.getName())&&Objects.equals(owner,v.getGenericDeclaration());}
        public int hashCode(){return Objects.hashCode(owner)^name.hashCode();}
        public String toString(){return name;}
    }
    static final class Wildcard implements WildcardType {
        final Type[] upper,lower;
        Wildcard(Type[] upper,Type[] lower){this.upper=upper;this.lower=lower;}
        public Type[] getUpperBounds(){return upper.clone();}
        public Type[] getLowerBounds(){return lower.clone();}
        public boolean equals(Object o){return o instanceof WildcardType w&&Arrays.equals(lower,w.getLowerBounds())&&Arrays.equals(upper,w.getUpperBounds());}
        public int hashCode(){return Arrays.hashCode(upper)^Arrays.hashCode(lower);}
        public String toString(){
            if(lower.length>0)return "? super "+join(lower);
            if(upper.length==0||upper[0]==Object.class)return "?";
            return "? extends "+join(upper);
        }
        static String join(Type[] t){StringBuilder s=new StringBuilder();for(int i=0;i<t.length;i++){if(i>0)s.append(" & ");s.append(t[i].getTypeName());}return s.toString();}
    }
    static final class GenericArray implements GenericArrayType {
        final Type component;
        GenericArray(Type component){this.component=component;}
        public Type getGenericComponentType(){return component;}
        public boolean equals(Object o){return o instanceof GenericArrayType g&&Objects.equals(component,g.getGenericComponentType());}
        public int hashCode(){return Objects.hashCode(component);}
        public String toString(){return component.getTypeName()+"[]";}
    }
}
