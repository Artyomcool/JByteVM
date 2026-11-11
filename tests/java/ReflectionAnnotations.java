import java.lang.annotation.*;
import java.lang.reflect.*;
public class ReflectionAnnotations {
    public enum Flavor {A,B}
    @Retention(RetentionPolicy.RUNTIME) public @interface Nested {String value() default "nested";}
    @Inherited @Retention(RetentionPolicy.RUNTIME) public @interface Mark {
        int value(); String text() default "default"; int[] numbers() default {2,3};
        Class<?> type() default int[][].class; Flavor flavor() default Flavor.B;
        Nested nested() default @Nested; Nested[] children() default {@Nested("first"),@Nested("second")};
        char letter() default 'x'; boolean yes() default true; long wide() default 12345678901L; float single() default 1.25f; double dbl() default -2.5;
    }
    @Retention(RetentionPolicy.RUNTIME) @Inherited @Repeatable(Tags.class) public @interface Tag {int value();}
    @Retention(RetentionPolicy.RUNTIME) @Inherited public @interface Tags {Tag[] value();}
    @Retention(RetentionPolicy.CLASS) public @interface Invisible {}
    @Mark(17) @Tag(4) @Tag(5) @Invisible public static class Parent {
        @Mark(21) public int field;
        @Mark(22) public Parent(){}
        @Mark(23) public void action(@Nested("parameter") String text,int n){}
    }
    public static class Child extends Parent {}
    @Mark(value=7,numbers={9},text="own") public static class Own extends Parent {}
    @Mark(17) public static class Same {}
    public static int values(int ignored)throws Exception {
        int n=0;Mark a=Parent.class.getAnnotation(Mark.class);
        if(a.value()==17&&a.text().equals("default")&&a.annotationType()==Mark.class)n|=1;
        if(a.type()==int[][].class&&a.flavor()==Flavor.B)n|=2;
        if(a.nested().value().equals("nested")&&a.children()[1].value().equals("second"))n|=4;
        if(a.letter()=='x'&&a.yes()&&a.wide()==12345678901L&&a.single()==1.25f&&a.dbl()==-2.5)n|=8;
        int[] numbers=a.numbers();numbers[0]=99;if(a.numbers()[0]==2)n|=16;
        if(Parent.class.getDeclaredAnnotations().length==2&&Parent.class.getAnnotation(Invisible.class)==null)n|=32;
        int[] defaults=(int[])Mark.class.getMethod("numbers").getDefaultValue();defaults[0]=99;if(((int[])Mark.class.getMethod("numbers").getDefaultValue())[0]==2)n|=64;
        if(Mark.class.isAnnotation()&&Mark.class.isInterface())n|=128;
        return n;
    }
    public static int members(int ignored)throws Exception {
        int n=0;
        if(Parent.class.getField("field").getAnnotation(Mark.class).value()==21)n|=1;
        if(Parent.class.getConstructor().getAnnotation(Mark.class).value()==22)n|=2;
        Method m=Parent.class.getMethod("action",String.class,int.class);
        if(m.getAnnotation(Mark.class).value()==23)n|=4;
        Annotation[][] p=m.getParameterAnnotations();if(p.length==2&&p[0].length==1&&p[1].length==0&&((Nested)p[0][0]).value().equals("parameter"))n|=8;
        if(Child.class.getDeclaredAnnotations().length==0&&Child.class.getAnnotation(Mark.class).value()==17)n|=16;
        if(Own.class.getAnnotation(Mark.class).value()==7&&Own.class.getAnnotations().length==2)n|=32;
        Tag[] tags=Parent.class.getAnnotationsByType(Tag.class);if(tags.length==2&&tags[0].value()==4&&tags[1].value()==5)n|=64;
        if(Child.class.getAnnotationsByType(Tag.class).length==2&&Child.class.getDeclaredAnnotationsByType(Tag.class).length==0)n|=128;
        return n;
    }
    public static int equality(int count)throws Exception {
        int n=0;Mark a=Parent.class.getAnnotation(Mark.class),b=Same.class.getAnnotation(Mark.class),c=Own.class.getAnnotation(Mark.class);
        if(a.equals(b)&&b.equals(a)&&!a.equals(c)&&!a.equals(null))n|=1;
        if(a.hashCode()==b.hashCode())n|=2;
        if(a.toString().contains("Mark")&&a.toString().contains("default"))n|=4;
        for(int i=0;i<count;i++){Mark copy=Same.class.getAnnotation(Mark.class);if(!a.equals(copy))return 0;copy.children()[0]=null;}
        if(b.children()[0]!=null)n|=8;
        return n;
    }
}
