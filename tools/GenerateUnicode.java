import java.nio.file.*;
public class GenerateUnicode {
    public static void main(String[] args) throws Exception {
        StringBuilder b=new StringBuilder("// Generated from the build JDK's Unicode digit data.\npackage jbv.runtime;\npublic final class Unicode {\n    private Unicode() {}\n    public static final int[] DIGIT_ZEROS={");
        boolean first=true;
        for(int c=0;c<=Character.MAX_CODE_POINT;c++)if(Character.digit(c,10)==0){if(!first)b.append(',');b.append(c);first=false;}
        b.append("};\n}\n");
        Path p=Path.of(args[0]);Files.createDirectories(p.getParent());
        if(!Files.exists(p)||!Files.readString(p).equals(b.toString()))Files.writeString(p,b.toString());
    }
}
