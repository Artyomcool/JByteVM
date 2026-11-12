package p29;
import java.io.*;
import java.util.Arrays;
/** A save format through DataOutputStream/DataInputStream, and resources of the JAR. */
public final class Main {
    static byte[] save(int seed) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(4);
        DataOutputStream out = new DataOutputStream(bytes);
        out.writeInt(0x48335356); out.writeInt(-seed); out.writeLong(0x0123456789abcdefL * seed);
        out.writeBoolean(true); out.writeBoolean(false); out.writeByte(-7); out.writeByte(300);
        out.writeShort(-2); out.writeShort(65535); out.writeChar('Ж');
        out.writeFloat(1.5f); out.writeFloat(Float.NaN); out.writeDouble(-0.0); out.writeDouble(Math.PI);
        out.writeUTF("hero Женя ☃ \u0000 end"); out.writeUTF("");
        byte[] block = {1, 2, 3, 4, 5};
        out.write(block, 1, 3); out.write(255); out.flush();
        String s = "" + out.size();
        out.close();
        byte[] all = bytes.toByteArray();
        return all.length + 0 == Integer.parseInt(s) ? all : null;
    }
    static String load(byte[] data) throws IOException {
        DataInputStream in = new DataInputStream(new ByteArrayInputStream(data));
        StringBuilder r = new StringBuilder();
        r.append(Integer.toHexString(in.readInt())).append(' ').append(in.readInt()).append(' ').append(in.readLong())
         .append(' ').append(in.readBoolean()).append(in.readBoolean()).append(' ').append(in.readByte()).append(' ').append(in.readUnsignedByte())
         .append(' ').append(in.readShort()).append(' ').append(in.readUnsignedShort()).append(' ').append((int) in.readChar())
         .append(' ').append(in.readFloat()).append(' ').append(in.readFloat()).append(' ').append(in.readDouble()).append(' ').append(in.readDouble())
         .append(" [").append(in.readUTF()).append("] [").append(in.readUTF()).append("] ").append(in.available());
        byte[] three = new byte[3];
        in.readFully(three);
        r.append(' ').append(Arrays.toString(three)).append(' ').append(in.read()).append(' ').append(in.read()).append(' ').append(in.available());
        try { in.readInt(); r.append(" no EOF"); } catch (EOFException e) { r.append(" EOF"); }
        in.close();
        return r.toString();
    }
    static String streams() throws IOException {
        StringBuilder r = new StringBuilder();
        ByteArrayInputStream in = new ByteArrayInputStream(new byte[]{10, 20, 30, 40, 50, 60}, 1, 4);
        byte[] b = new byte[8];
        r.append(in.available()).append(' ').append(in.read()).append(' ').append(in.read(b, 2, 5)).append(' ').append(Arrays.toString(b))
         .append(' ').append(in.read(b, 0, 1)).append(' ').append(in.available());
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (int i = 0; i < 100; i++) out.write(i * 7);
        out.write(new byte[]{9, 8, 7});
        r.append(' ').append(out.size()).append(' ').append(Arrays.hashCode(out.toByteArray()));
        DataInputStream truncated = new DataInputStream(new ByteArrayInputStream(new byte[]{0, 5, 'a', 'b'}));
        try { truncated.readUTF(); r.append(" no EOF"); } catch (EOFException e) { r.append(" UTF EOF"); }
        try { new DataInputStream(new ByteArrayInputStream(new byte[]{0, 1, (byte) 0x80})).readUTF(); r.append(" no error"); }
        catch (UTFDataFormatException e) { r.append(" UTF malformed"); }
        InputStream generic = new FilterInputStream(new ByteArrayInputStream(new byte[]{1, 2, 3})) {};
        r.append(' ').append(generic.read(new byte[5], 0, 5)).append(' ').append(generic.read());
        return r.toString();
    }
    static String resource(String name) throws IOException {
        InputStream in = Main.class.getResourceAsStream(name);
        if (in == null) return name + "=null";
        int available = in.available();
        byte[] data = in.readAllBytes();
        in.close();
        return name + "=" + available + ":" + data.length + ":" + Arrays.hashCode(data) + ":" + new String(data, 0, Math.min(12, data.length), "UTF-8");
    }
    static String ascii(String s) {
        StringBuilder r = new StringBuilder();
        for (int i = 0; i < s.length(); i++) { char c = s.charAt(i); if (c >= 32 && c < 127) r.append(c); else r.append('<').append(Integer.toHexString(c)).append('>'); }
        return r.toString();
    }
    public static String run() throws IOException {
        String r = load(save(3)) + " | " + load(save(-41)) + " | " + streams();
        r += " | " + resource("/farhut.def") + " " + resource("data/table.txt") + " " + resource("/p29/data/table.txt")
           + " " + resource("/missing.bin") + " " + resource("missing.txt") + " " + resource("/big.bin");
        DataInputStream def = new DataInputStream(Main.class.getResourceAsStream("/farhut.def"));
        r += " | " + Integer.toHexString(def.readInt()) + " " + def.readUTF();
        return ascii(r);
    }
}
