import java.io.*;
public class TextOracle {
    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        for (String line; (line = input.readLine()) != null;) {
            String[] p = line.split(" ");
            Object result;
            if (p[0].equals("F")) result = Strings.fmtF(Float.intBitsToFloat(Integer.parseUnsignedInt(p[1],16)));
            else if (p[0].equals("D")) result = Strings.fmtD(Double.longBitsToDouble(Long.parseUnsignedLong(p[1],16)));
            else result = Strings.class.getMethod(p[1]).invoke(null);
            if (result instanceof String s) {
                StringBuilder encoded = new StringBuilder();
                for (int i=0; i<s.length(); i++) {
                    String h = Integer.toHexString(s.charAt(i));
                    encoded.append("0000",0,4-h.length()).append(h);
                }
                System.out.println(encoded);
            } else System.out.println(result);
        }
    }
}
