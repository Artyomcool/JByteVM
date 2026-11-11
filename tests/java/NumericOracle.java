import java.io.*;
import java.lang.reflect.*;
public class NumericOracle {
    public static void main(String[] args) throws Exception {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        for (String line; (line = in.readLine()) != null;) {
            String[] p = line.split(" ");
            String d = p[1]; int count = d.indexOf(')') - 1;
            Class<?>[] types = new Class<?>[count]; Object[] values = new Object[count];
            for (int i = 0; i < count; ++i) {
                long bits = Long.parseUnsignedLong(p[i + 2], 16);
                switch (d.charAt(i + 1)) {
                case 'I': types[i] = int.class; values[i] = (int)bits; break;
                case 'J': types[i] = long.class; values[i] = bits; break;
                case 'F': types[i] = float.class; values[i] = Float.intBitsToFloat((int)bits); break;
                default: types[i] = double.class; values[i] = Double.longBitsToDouble(bits); break;
                }
            }
            String[] target=p[0].split("#");
            Method method = (target.length==1?Numbers.class:Class.forName(target[0])).getMethod(target[target.length-1], types);
            Object value = method.invoke(null, values);
            long bits = switch (d.charAt(d.length() - 1)) {
                case 'J' -> (Long)value;
                case 'D' -> Double.doubleToRawLongBits((Double)value);
                case 'F' -> Integer.toUnsignedLong(Float.floatToRawIntBits((Float)value));
                default -> Integer.toUnsignedLong((Integer)value);
            };
            System.out.println(Long.toUnsignedString(bits, 16));
        }
    }
}
