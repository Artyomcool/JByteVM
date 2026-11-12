package java.io;
public class ByteArrayOutputStream extends OutputStream {
    protected byte[] buf;
    protected int count;
    public ByteArrayOutputStream() { this(32); }
    public ByteArrayOutputStream(int size) {
        if(size<0)throw new IllegalArgumentException("Negative initial size: "+size);
        buf=new byte[size];
    }
    private void room(int n) {
        if(n-buf.length>0){int c=Math.max(buf.length<<1,n);byte[] b=new byte[c];System.arraycopy(buf,0,b,0,count);buf=b;}
    }
    public void write(int b) { room(count+1);buf[count++]=(byte)b; }
    public void write(byte[] b,int off,int len) {
        if(off<0||len<0||len>b.length-off)throw new IndexOutOfBoundsException();
        room(count+len);System.arraycopy(b,off,buf,count,len);count+=len;
    }
    public void writeBytes(byte[] b) { write(b,0,b.length); }
    public void writeTo(OutputStream out) throws IOException { out.write(buf,0,count); }
    public void reset() { count=0; }
    public byte[] toByteArray() { byte[] r=new byte[count];System.arraycopy(buf,0,r,0,count);return r; }
    public int size() { return count; }
    public String toString() { return new String(buf,0,count); }
    public void close() {}
}
