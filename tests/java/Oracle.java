import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;

// Reference results come from HotSpot, including Java integer corner cases.
public class Oracle {
    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        for (String line; (line = input.readLine()) != null;) {
            String[] parts = line.split(" ");
            Class<?>[] types = new Class<?>[parts.length - 1];
            Object[] values = new Object[types.length];
            for (int i = 0; i < types.length; ++i) {
                types[i] = int.class;
                values[i] = Integer.parseInt(parts[i + 1]);
            }
            int split = parts[0].indexOf('#');
            Class<?> owner = split < 0 ? Core.class : Class.forName(parts[0].substring(0, split));
            String name = split < 0 ? parts[0] : parts[0].substring(split + 1);
            Method method = owner.getMethod(name, types);
            System.out.println(method.invoke(null, values));
        }
    }
}
