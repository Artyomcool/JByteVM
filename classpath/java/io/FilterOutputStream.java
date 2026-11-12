package java.io;
public class FilterOutputStream extends OutputStream {
    protected OutputStream out;
    private boolean closed;
    public FilterOutputStream(OutputStream out) { this.out=out; }
    public void write(int b) throws IOException { out.write(b); }
    public void write(byte[] b) throws IOException { write(b,0,b.length); }
    public void write(byte[] b,int off,int len) throws IOException {
        if(off<0||len<0||len>b.length-off)throw new IndexOutOfBoundsException();
        for(int i=0;i<len;i++)write(b[off+i]);
    }
    public void flush() throws IOException { out.flush(); }
    public void close() throws IOException { if(closed)return;closed=true;try{flush();}finally{out.close();} }
}
