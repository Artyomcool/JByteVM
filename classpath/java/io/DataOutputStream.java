package java.io;
/** Big-endian primitives and modified UTF-8, as java.io.DataOutputStream. */
public class DataOutputStream extends FilterOutputStream implements DataOutput {
    protected int written;
    public DataOutputStream(OutputStream out) { super(out); }
    private void count(int n) { written+=n;if(written<0)written=Integer.MAX_VALUE; }
    public void write(int b) throws IOException { out.write(b);count(1); }
    public void write(byte[] b,int off,int len) throws IOException { out.write(b,off,len);count(len); }
    public void flush() throws IOException { out.flush(); }
    public final void writeBoolean(boolean v) throws IOException { write(v?1:0); }
    public final void writeByte(int v) throws IOException { write(v); }
    public final void writeShort(int v) throws IOException { write(new byte[]{(byte)(v>>8),(byte)v},0,2); }
    public final void writeChar(int v) throws IOException { writeShort(v); }
    public final void writeInt(int v) throws IOException { write(new byte[]{(byte)(v>>24),(byte)(v>>16),(byte)(v>>8),(byte)v},0,4); }
    public final void writeLong(long v) throws IOException {
        byte[] b=new byte[8];for(int i=0;i<8;i++)b[i]=(byte)(v>>(56-8*i));write(b,0,8);
    }
    public final void writeFloat(float v) throws IOException { writeInt(Float.floatToIntBits(v)); }
    public final void writeDouble(double v) throws IOException { writeLong(Double.doubleToLongBits(v)); }
    public final void writeBytes(String s) throws IOException { for(int i=0;i<s.length();i++)write(s.charAt(i)); }
    public final void writeChars(String s) throws IOException { for(int i=0;i<s.length();i++)writeChar(s.charAt(i)); }
    public final void writeUTF(String s) throws IOException {
        int length=0;
        for(int i=0;i<s.length();i++){char c=s.charAt(i);length+=c>=1&&c<0x80?1:c<0x800?2:3;}
        if(length>65535)throw new UTFDataFormatException("encoded string too long: "+length+" bytes");
        byte[] b=new byte[length+2];b[0]=(byte)(length>>8);b[1]=(byte)length;int n=2;
        for(int i=0;i<s.length();i++){
            char c=s.charAt(i);
            if(c>=1&&c<0x80)b[n++]=(byte)c;
            else if(c<0x800){b[n++]=(byte)(0xc0|c>>6);b[n++]=(byte)(0x80|c&0x3f);}
            else{b[n++]=(byte)(0xe0|c>>12);b[n++]=(byte)(0x80|c>>6&0x3f);b[n++]=(byte)(0x80|c&0x3f);}
        }
        write(b,0,n);
    }
    public final int size() { return written; }
}
