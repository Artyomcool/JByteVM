package java.io;
public abstract class InputStream implements Closeable {
    public InputStream() {}
    public abstract int read() throws IOException;
    public int read(byte[] b) throws IOException { return read(b,0,b.length); }
    public int read(byte[] b,int off,int len) throws IOException {
        if(off<0||len<0||len>b.length-off)throw new IndexOutOfBoundsException();
        if(len==0)return 0;
        int c=read();if(c<0)return -1;
        b[off]=(byte)c;int i=1;
        for(;i<len;i++){c=read();if(c<0)break;b[off+i]=(byte)c;}
        return i;
    }
    public byte[] readAllBytes() throws IOException {
        byte[] all=new byte[0];byte[] chunk=new byte[256];int n;
        while((n=read(chunk,0,chunk.length))>0){byte[] grown=new byte[all.length+n];System.arraycopy(all,0,grown,0,all.length);System.arraycopy(chunk,0,grown,all.length,n);all=grown;}
        return all;
    }
    public int readNBytes(byte[] b,int off,int len) throws IOException {
        int n=0;while(n<len){int r=read(b,off+n,len-n);if(r<0)break;n+=r;}return n;
    }
    public long skip(long n) throws IOException { long k=0;while(k<n&&read()>=0)k++;return k; }
    public int available() throws IOException { return 0; }
    public void close() throws IOException {}
    public void mark(int limit) {}
    public void reset() throws IOException { throw new IOException("mark/reset not supported"); }
    public boolean markSupported() { return false; }
    public long transferTo(OutputStream out) throws IOException {
        byte[] b=new byte[256];long t=0;int n;while((n=read(b,0,b.length))>0){out.write(b,0,n);t+=n;}return t;
    }
}
