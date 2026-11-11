package java.lang.annotation;
public interface Annotation { Class<? extends Annotation> annotationType(); boolean equals(Object other); int hashCode(); String toString(); }
