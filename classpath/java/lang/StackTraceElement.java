package java.lang;
import java.util.Objects;
public final class StackTraceElement implements java.io.Serializable {
    // First four fields form the VM's compact stack-frame record.
    private final String declaringClass,methodName,fileName;private final int lineNumber;
    private final String classLoaderName,moduleName,moduleVersion;
    public StackTraceElement(String declaringClass,String methodName,String fileName,int lineNumber){this(null,null,null,declaringClass,methodName,fileName,lineNumber);}
    public StackTraceElement(String loader,String module,String version,String declaringClass,String methodName,String fileName,int lineNumber){this.declaringClass=Objects.requireNonNull(declaringClass);this.methodName=Objects.requireNonNull(methodName);this.fileName=fileName;this.lineNumber=lineNumber;classLoaderName=loader;moduleName=module;moduleVersion=version;}
    public String getClassName(){return declaringClass;}public String getMethodName(){return methodName;}public String getFileName(){return fileName;}public int getLineNumber(){return lineNumber;}
    public String getClassLoaderName(){return classLoaderName;}public String getModuleName(){return moduleName;}public String getModuleVersion(){return moduleVersion;}
    public boolean isNativeMethod(){return lineNumber==-2;}
    public String toString(){StringBuilder b=new StringBuilder();if(classLoaderName!=null&&!classLoaderName.isEmpty())b.append(classLoaderName).append('/');if(moduleName!=null){b.append(moduleName);if(moduleVersion!=null)b.append('@').append(moduleVersion);}if(b.length()!=0)b.append('/');b.append(declaringClass).append('.').append(methodName).append('(');if(isNativeMethod())b.append("Native Method");else if(fileName==null)b.append("Unknown Source");else {b.append(fileName);if(lineNumber>=0)b.append(':').append(lineNumber);}return b.append(')').toString();}
    public boolean equals(Object o){if(!(o instanceof StackTraceElement))return false;StackTraceElement s=(StackTraceElement)o;return lineNumber==s.lineNumber&&declaringClass.equals(s.declaringClass)&&methodName.equals(s.methodName)&&Objects.equals(fileName,s.fileName)&&Objects.equals(classLoaderName,s.classLoaderName)&&Objects.equals(moduleName,s.moduleName)&&Objects.equals(moduleVersion,s.moduleVersion);}
    public int hashCode(){int h=31*declaringClass.hashCode()+methodName.hashCode();h=31*h+Objects.hashCode(classLoaderName);h=31*h+Objects.hashCode(moduleName);h=31*h+Objects.hashCode(moduleVersion);h=31*h+Objects.hashCode(fileName);return 31*h+lineNumber;}
}
