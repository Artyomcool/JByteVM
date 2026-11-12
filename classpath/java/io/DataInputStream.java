package java.io;
/** Big-endian primitives and modified UTF-8, as java.io.DataInputStream. */
public class DataInputStream extends FilterInputStream implements DataInput {
    public DataInputStream(InputStream in) { super(in); }
    public final int read(byte[] b) throws IOException { return in.read(b,0,b.length); }
    public final int read(byte[] b,int off,int len) throws IOException { return in.read(b,off,len); }
    public final void readFully(byte[] b) throws IOException { readFully(b,0,b.length); }
    public final void readFully(byte[] b,int off,int len) throws IOException {
        if(len<0)throw new IndexOutOfBoundsException();
        int n=0;while(n<len){int r=in.read(b,off+n,len-n);if(r<0)throw new EOFException();n+=r;}
    }
    public final int skipBytes(int n) throws IOException { int k=0;while(k<n){long s=in.skip(n-k);if(s<=0)break;k+=(int)s;}return k; }
    private int next() throws IOException { int c=in.read();if(c<0)throw new EOFException();return c; }
    public final boolean readBoolean() throws IOException { return next()!=0; }
    public final byte readByte() throws IOException { return (byte)next(); }
    public final int readUnsignedByte() throws IOException { return next(); }
    public final short readShort() throws IOException { return (short)readUnsignedShort(); }
    public final int readUnsignedShort() throws IOException { int a=next();return a<<8|next(); }
    public final char readChar() throws IOException { return (char)readUnsignedShort(); }
    public final int readInt() throws IOException { int a=next(),b=next(),c=next();return a<<24|b<<16|c<<8|next(); }
    public final long readLong() throws IOException { long h=readInt();return h<<32|readInt()&0xffffffffL; }
    public final float readFloat() throws IOException { return Float.intBitsToFloat(readInt()); }
    public final double readDouble() throws IOException { return Double.longBitsToDouble(readLong()); }
    public final String readUTF() throws IOException { return readUTF(this); }
    public static final String readUTF(DataInput in) throws IOException {
        int length=in.readUnsignedShort();
        byte[] b=new byte[length];in.readFully(b,0,length);
        char[] c=new char[length];int n=0;
        for(int i=0;i<length;){
            int x=b[i]&255;
            if(x<0x80){c[n++]=(char)x;i++;}
            else if((x>>5)==6){
                if(i+2>length)throw new UTFDataFormatException("malformed input: partial character at end");
                int y=b[i+1];if((y&0xc0)!=0x80)throw new UTFDataFormatException("malformed input around byte "+(i+1));
                c[n++]=(char)((x&0x1f)<<6|y&0x3f);i+=2;
            }else if((x>>4)==14){
                if(i+3>length)throw new UTFDataFormatException("malformed input: partial character at end");
                int y=b[i+1],z=b[i+2];if((y&0xc0)!=0x80||(z&0xc0)!=0x80)throw new UTFDataFormatException("malformed input around byte "+(i+2));
                c[n++]=(char)((x&0x0f)<<12|(y&0x3f)<<6|z&0x3f);i+=3;
            }else throw new UTFDataFormatException("malformed input around byte "+i);
        }
        return new String(c,0,n);
    }
}
