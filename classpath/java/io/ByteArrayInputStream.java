package java.io;
public class ByteArrayInputStream extends InputStream {
    protected byte[] buf;
    protected int pos,mark,count;
    public ByteArrayInputStream(byte[] buf) { this.buf=buf;this.count=buf.length; }
    public ByteArrayInputStream(byte[] buf,int offset,int length) {
        this.buf=buf;this.pos=offset;this.mark=offset;this.count=Math.min(offset+length,buf.length);
    }
    public int read() { return pos<count?buf[pos++]&255:-1; }
    public int read(byte[] b,int off,int len) {
        if(off<0||len<0||len>b.length-off)throw new IndexOutOfBoundsException();
        if(pos>=count)return -1;
        int n=Math.min(len,count-pos);
        if(n<=0)return 0;
        System.arraycopy(buf,pos,b,off,n);pos+=n;return n;
    }
    public byte[] readAllBytes() { byte[] r=new byte[count-pos];System.arraycopy(buf,pos,r,0,r.length);pos=count;return r; }
    public int readNBytes(byte[] b,int off,int len) { int n=read(b,off,len);return n<0?0:n; }
    public long skip(long n) { long k=Math.max(0,Math.min(n,count-pos));pos+=(int)k;return k; }
    public int available() { return count-pos; }
    public boolean markSupported() { return true; }
    public void mark(int limit) { mark=pos; }
    public void reset() { pos=mark; }
    public void close() {}
}
