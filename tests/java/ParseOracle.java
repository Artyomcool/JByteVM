import java.io.*;
public class ParseOracle {
    public static void main(String[] args)throws Exception {
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in));
        for(String line;(line=in.readLine())!=null;) {
            char[] text=new char[(line.length()-2)/4];
            for(int i=0;i<text.length;i++)text[i]=(char)Integer.parseInt(line.substring(2+4*i,6+4*i),16);
            String s=new String(text);
            System.out.println(Long.toUnsignedString(line.charAt(0)=='F'?LibraryValues.parseF(s):LibraryValues.parseD(s),16));
        }
    }
}
