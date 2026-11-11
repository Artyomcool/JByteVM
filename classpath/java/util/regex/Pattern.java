package java.util.regex;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/** Backtracking regular expressions with java.util.regex semantics (the node graph mirrors the JDK design). */
public final class Pattern implements java.io.Serializable {
    public static final int UNIX_LINES=1, CASE_INSENSITIVE=2, COMMENTS=4, MULTILINE=8, LITERAL=16, DOTALL=32,
        UNICODE_CASE=64, CANON_EQ=128, UNICODE_CHARACTER_CLASS=256;
    // Node types.
    static final int ACC=0, LASTN=1, START=2, BEGIN=3, END=4, CARET=5, LASTM=6, DOLLAR=7, LINE=8, PROP=9, QUES=10, GPROP=11,
        CURLY=12, GCURLY=13, CONN=14, BRANCH=15, GHEAD=16, GTAIL=17, PROLOG=18, LOOP=19, BREF=20, POS=21, BEHIND=22, LBEND=23,
        BOUND=24, EMPTY=25, MAX=0x7fffffff;
    static final class Node {
        int t, a, b, c, d, e, f=-1;
        Node next, atom; Node[] alts; int[] set;
        Node(int t) { this.t=t; next=ACCEPT; }
    }
    static final Node ACCEPT=new Node(ACC), LAST=new Node(LASTN);
    static final int[] DIGIT=set("09"), WORD=set("09AZ__az"), SPACE=set("\t\r  "), VWS=set("\n\r\u0085\u0085\u2028\u2029"),
        HWS=set("\t\t  \u00a0\u00a0\u1680\u1680\u180e\u180e\u2000\u200a\u202f\u202f\u205f\u205f\u3000\u3000"), ALL={0,0x10ffff};
    private static final String POSIX="Lower Upper ASCII Alpha Digit Alnum Punct Graph Print Blank Cntrl XDigit Space L1 all ";
    private static final String[] POSIX_SETS={"az","AZ","\0\u007f","AZaz","09","09AZaz","!/:@[`{~","!~"," ~","\t\t  ","\0\u001f\u007f\u007f","09AFaf","\t\r  ","\0\u00ff"};

    private final String pattern;
    private final int flags;
    private int flags0;
    Node root, matchRoot;
    int groupCount=1, localCount, posCount;
    HashMap<String,Integer> names;
    // Compilation state.
    private int[] temp, pred;
    private int cursor, plen, smin, smax;
    private boolean hasRef, supp, svalid, sdet;
    private Node out;
    private ArrayList<Node> top;

    private Pattern(String p, int f) {
        if((f&~511)!=0)throw new IllegalArgumentException("Unknown flag 0x"+Integer.toHexString(f));
        pattern=p; flags=flags0=f;
        if((f&(UNICODE_CASE|CANON_EQ|UNICODE_CHARACTER_CLASS))!=0)throw new PatternSyntaxException("Unsupported flag (UNICODE_CASE, CANON_EQ and UNICODE_CHARACTER_CLASS are not implemented)",p,-1);
        if(p.isEmpty()){ matchRoot=LAST; root=start(LAST); } else compile();
    }
    public static Pattern compile(String regex) { return new Pattern(regex,0); }
    public static Pattern compile(String regex, int flags) { return new Pattern(regex,flags); }
    public String pattern() { return pattern; }
    public String toString() { return pattern; }
    public int flags() { return flags0; }
    public Matcher matcher(CharSequence input) { return new Matcher(this,input); }
    public static boolean matches(String regex, CharSequence input) { return compile(regex).matcher(input).matches(); }
    public Map<String,Integer> namedGroups() { return Collections.unmodifiableMap(names==null?new HashMap<String,Integer>():names); }
    public String[] split(CharSequence input) { return split(input,0,false); }
    public String[] split(CharSequence input, int limit) { return split(input,limit,false); }
    public String[] splitWithDelimiters(CharSequence input, int limit) { return split(input,limit,true); }
    private String[] split(CharSequence input, int limit, boolean delims) {
        int count=0, index=0;
        ArrayList<String> list=new ArrayList<>();
        Matcher m=matcher(input);
        while(m.find()) {
            if(limit<=0||count<limit-1) {
                if(index==0&&m.start()==0&&m.end()==0)continue;
                list.add(input.subSequence(index,m.start()).toString());
                index=m.end();
                if(delims)list.add(input.subSequence(m.start(),index).toString());
                count++;
            } else if(count==limit-1) {
                list.add(input.subSequence(index,input.length()).toString());
                index=m.end(); count++;
            }
        }
        if(index==0)return new String[]{input.toString()};
        if(limit<=0||count<limit)list.add(input.subSequence(index,input.length()).toString());
        int n=list.size();
        if(limit==0)while(n>0&&list.get(n-1).isEmpty())n--;
        String[] r=new String[n];
        for(int i=0;i<n;i++)r[i]=list.get(i);
        return r;
    }
    public static String quote(String s) {
        StringBuilder sb=new StringBuilder("\\Q");
        int at=0, e;
        while((e=s.indexOf("\\E",at))>=0) { sb.append(s,at,e).append("\\E\\\\E\\Q"); at=e+2; }
        return sb.append(s,at,s.length()).append("\\E").toString();
    }

    // ---- compilation ----
    private void compile() {
        String p=pattern; int n=p.length(), k=0;
        temp=new int[n+2];
        for(int x=0;x<n;) {
            int c=p.charAt(x++);
            if(Character.isHighSurrogate((char)c)&&x<n&&Character.isLowSurrogate(p.charAt(x)))c=Character.toCodePoint((char)c,p.charAt(x++));
            if(c>=0xd800)supp|=c>=0x10000||c<0xe000;
            temp[k++]=c;
        }
        plen=k;
        top=new ArrayList<>();
        if(has(LITERAL)) {
            Node h=LAST;
            while(--k>=0) { Node c=prop(single(temp[k])); c.next=h; h=c; }
            matchRoot=h;
        } else {
            removeQE();
            matchRoot=expr(LAST);
            if(plen!=cursor) {
                if(peek()==')')throw error("Unmatched closing ')'");
                if(cursor==plen+1&&temp[plen-1]=='\\')throw error("Unescaped trailing backslash");
                throw error("Unexpected internal error");
            }
        }
        root=matchRoot.t==BEGIN?matchRoot:start(matchRoot);
        if(!hasRef)for(Node l:top)if(l.t==LOOP)l.f=posCount++;
        temp=null; top=null;
    }
    private Node start(Node next) {
        Node s=new Node(START); s.next=next;
        reset(); study(next); s.a=smin; s.b=supp?1:0;
        return s;
    }
    private void removeQE() {
        int i=0;
        while(i<plen-1) { if(temp[i]!='\\')i++; else if(temp[i+1]!='Q')i+=2; else break; }
        if(i>=plen-1)return;
        int j=i; i+=2;
        int[] t=new int[j+2+3*(plen-i)+2];
        System.arraycopy(temp,0,t,0,j);
        boolean in=true, begin=true;
        while(i<plen) {
            int c=temp[i++];
            if(c>=128||alpha(c))t[j++]=c;
            else if(c>='0'&&c<='9') { if(begin){t[j++]='\\';t[j++]='x';t[j++]='3';} t[j++]=c; }
            else if(c!='\\') { if(in)t[j++]='\\'; t[j++]=c; }
            else if(in) { if(temp[i]=='E'){i++;in=false;} else {t[j++]='\\';t[j++]='\\';} }
            else if(temp[i]=='Q') { i++; in=begin=true; continue; }
            else { t[j++]=c; if(i!=plen)t[j++]=temp[i++]; }
            begin=false;
        }
        plen=j; temp=Arrays.copyOf(t,j+2);
    }
    private boolean has(int f) { return (flags0&f)!=0; }
    private static boolean alpha(int c) { return (c|32)>='a'&&(c|32)<='z'; }
    private static boolean digit(int c) { return c>='0'&&c<='9'; }
    private static boolean space(int c) { return c==' '||c>=9&&c<=13; }
    private int peek() { int c=temp[cursor]; return has(COMMENTS)?past(c):c; }
    private int read() { int c=temp[cursor++]; if(has(COMMENTS)){cursor--;c=past(c);cursor++;} return c; }
    private int next() { int c=temp[++cursor]; return has(COMMENTS)?past(c):c; }
    private int nextEscaped() { return temp[++cursor]; }
    private int skip() { cursor+=2; return temp[cursor-1]; }
    private void unread() { cursor--; }
    /** Skips COMMENTS-mode whitespace and comments starting at cursor (which holds c), leaving cursor on the result. */
    private int past(int c) {
        while(space(c)||c=='#') {
            while(space(c))c=temp[++cursor];
            if(c=='#') {
                while((c=temp[++cursor])!=0&&!(c=='\n'||!has(UNIX_LINES)&&(c=='\r'||(c|1)==0x2029||c==0x85))) {}
                if(c==0&&cursor>plen)c=temp[cursor=plen];
            }
        }
        return c;
    }
    private PatternSyntaxException error(String s) { return new PatternSyntaxException(s,pattern,cursor-1); }
    private Node node(int t, Node atom, int a, int b) { Node n=new Node(t); n.atom=atom; n.a=a; n.b=b; return n; }
    private Node prop(int[] set) {
        if(isWide(set))supp=true;
        Node n=new Node(PROP); n.set=set; return n;
    }

    private Node expr(Node end) {
        Node prev=null, firstTail=null, conn=null, branch=null;
        ArrayList<Node> alts=null;
        for(;;) {
            Node node=sequence(end), tail=out;
            if(prev==null) { prev=node; firstTail=tail; }
            else {
                if(conn==null) { conn=new Node(CONN); conn.next=end; }
                if(node==end)node=null; else tail.next=conn;
                if(prev==branch)alts.add(node);
                else {
                    if(prev==end)prev=null; else firstTail.next=conn;
                    alts=new ArrayList<>(); alts.add(prev); alts.add(node);
                    prev=branch=node(BRANCH,conn,0,0);
                }
            }
            if(peek()!='|') { if(branch!=null)branch.alts=alts.toArray(new Node[0]); return prev; }
            next();
        }
    }
    private Node sequence(Node end) {
        Node head=null, tail=null, node;
        loop: for(;;) {
            int ch=peek();
            switch(ch) {
            case '(':
                node=group0();
                if(node==null)continue;
                if(head==null)head=node; else tail.next=node;
                tail=out;
                continue;
            case '[': node=prop(clazz(true)); break;
            case '\\':
                ch=nextEscaped();
                if(ch=='p'||ch=='P') node=prop(family(ch));
                else { unread(); node=atom(); }
                break;
            case '^': next(); node=has(MULTILINE)?node(CARET,null,has(UNIX_LINES)?1:0,0):new Node(BEGIN); break;
            case '$': next(); node=node(DOLLAR,null,has(MULTILINE)?1:0,has(UNIX_LINES)?1:0); break;
            case '.': next(); node=new Node(PROP); node.set=has(DOTALL)?ALL:not(set(has(UNIX_LINES)?"\n\n":"\n\n\r\r\u0085\u0085\u2028\u2029")); break;
            case '|': case ')': break loop;
            case '?': case '*': case '+': next(); throw error("Dangling meta character '"+(char)ch+"'");
            case 0: if(cursor>=plen)break loop;
            default: node=atom();
            }
            node=closure(node);
            if(head==null)head=tail=node; else { tail.next=node; tail=node; }
            while(tail.next!=ACCEPT)tail=tail.next;
        }
        if(head==null)return end;
        tail.next=end; out=tail;
        return head;
    }
    private Node atom() {
        int first=0, prev=-1;
        int[] buf=new int[16];
        int ch=peek();
        for(;;) {
            switch(ch) {
            case '*': case '+': case '?': case '{':
                if(first>1) { cursor=prev; first--; }
                break;
            case '$': case '.': case '^': case '(': case '[': case '|': case ')':
                break;
            case '\\':
                ch=nextEscaped();
                if(ch=='p'||ch=='P') {
                    if(first>0) { unread(); break; }
                    return prop(family(ch));
                }
                unread(); prev=cursor;
                ch=escape(false,first==0,false);
                if(ch>=0) {
                    if(first==buf.length)buf=Arrays.copyOf(buf,first*2);
                    buf[first++]=ch; ch=peek(); continue;
                }
                if(first==0)return out;
                cursor=prev;
                break;
            case 0:
                if(cursor>=plen)break;
            default:
                prev=cursor;
                if(first==buf.length)buf=Arrays.copyOf(buf,first*2);
                buf[first++]=ch; ch=next(); continue;
            }
            break;
        }
        if(first==0)return new Node(EMPTY);
        Node h=prop(single(buf[0])), t=h;
        for(int i=1;i<first;i++)t=t.next=prop(single(buf[i]));
        return h;
    }
    private Node ref(int r) {
        for(int ch;digit(ch=peek());read()) {
            int n=r*10+ch-'0';
            if(groupCount-1<n)break;
            r=n;
        }
        return backref(r);
    }
    private Node backref(int r) { hasRef=true; return node(BREF,null,r*2,has(CASE_INSENSITIVE)?1:0); }
    /** Returns a code point, or -1 after creating a node in {@code out} (or a set in {@code pred} when inclass). */
    private int escape(boolean inclass, boolean create, boolean isrange) {
        int ch=skip();
        int[] p=null;
        switch(ch) {
        case '0': return octal();
        case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
            if(inclass)break;
            if(create)out=ref(ch-'0');
            return -1;
        case 'A': case 'B': case 'G': case 'R': case 'Z': case 'z': case 'X':
            if(inclass)break;
            if(create) {
                if(ch=='X')throw error("Unsupported escape sequence \\X");
                out=ch=='A'?new Node(BEGIN):ch=='B'?node(BOUND,null,4,0):ch=='G'?new Node(LASTM):ch=='R'?new Node(LINE)
                    :ch=='Z'?node(DOLLAR,null,0,has(UNIX_LINES)?1:0):new Node(END);
            }
            return -1;
        case 'b':
            if(inclass)break;
            if(create) {
                if(peek()=='{') { if(skip()=='g')throw error("Unsupported escape sequence \\b{g}"); unread(); unread(); }
                out=node(BOUND,null,3,0);
            }
            return -1;
        case 'N': throw error("Unsupported escape sequence \\N");
        case 'k':
            if(inclass)break;
            if(read()!='<')throw error("\\k is not followed by '<' for named capturing group");
            String name=groupname(read());
            Integer number=names==null?null:names.get(name);
            if(number==null)throw error("named capturing group <"+name+"> does not exist");
            if(create)out=backref(number);
            return -1;
        case 'a': return 7;
        case 'c': if(cursor<plen)return read()^64; throw error("Illegal control escape sequence");
        case 'e': return 27;
        case 'f': return '\f';
        case 'n': return '\n';
        case 'r': return '\r';
        case 't': return '\t';
        case 'u': return unicode();
        case 'x': return hex();
        case 'v': if(isrange)return 11; p=VWS; break;
        case 'V': p=wide(not(VWS)); break;
        case 'h': p=HWS; break;
        case 'H': p=wide(not(HWS)); break;
        case 'd': p=DIGIT; break;
        case 'D': p=wide(not(DIGIT)); break;
        case 's': p=SPACE; break;
        case 'S': p=wide(not(SPACE)); break;
        case 'w': p=WORD; break;
        case 'W': p=wide(not(WORD)); break;
        default: if(!alpha(ch))return ch;
        }
        if(p==null)throw error("Illegal/unsupported escape sequence");
        if(create) { pred=p; if(!inclass)out=prop(p); }
        return -1;
    }
    private int octal() {
        int n=read();
        if(n>='0'&&n<='7') {
            int m=read();
            if(m>='0'&&m<='7') {
                int o=read();
                if(o>='0'&&o<='7'&&n<='3')return (n-'0')*64+(m-'0')*8+o-'0';
                unread(); return (n-'0')*8+m-'0';
            }
            unread(); return n-'0';
        }
        throw error("Illegal octal escape sequence");
    }
    private static int hexDigit(int c) { return digit(c)?c-'0':alpha(c)&&(c|32)<='f'?(c|32)-'a'+10:-1; }
    private int hex() {
        int n=read();
        if(hexDigit(n)>=0) { int m=read(); if(hexDigit(m)>=0)return hexDigit(n)*16+hexDigit(m); }
        else if(n=='{'&&hexDigit(peek())>=0) {
            int ch=0;
            while(hexDigit(n=read())>=0) { ch=ch*16+hexDigit(n); if(ch>0x10ffff)throw error("Hexadecimal codepoint is too big"); }
            if(n!='}')throw error("Unclosed hexadecimal escape sequence");
            return ch;
        }
        throw error("Illegal hexadecimal escape sequence");
    }
    private int u4() {
        int n=0;
        for(int i=0;i<4;i++) { int d=hexDigit(read()); if(d<0)throw error("Illegal Unicode escape sequence"); n=n*16+d; }
        return n;
    }
    private int unicode() {
        int n=u4();
        if(Character.isHighSurrogate((char)n)) {
            int cur=cursor;
            if(read()=='\\'&&read()=='u') { int m=u4(); if(Character.isLowSurrogate((char)m))return Character.toCodePoint((char)n,(char)m); }
            cursor=cur;
        }
        return n;
    }
    private int[] family(int p) {
        int ch=next();
        if(ch!='{')unread();
        next();
        String name;
        if(ch!='{') { int c=temp[cursor]; name=new String(Character.toChars(c)); read(); }
        else {
            int i=cursor;
            temp[plen]='}';
            while(read()!='}') {}
            temp[plen]=0;
            if(cursor>plen)throw error("Unclosed character family");
            if(i+1>=cursor)throw error("Empty character family");
            StringBuilder sb=new StringBuilder();
            for(int j=i;j<cursor-1;j++)sb.appendCodePoint(temp[j]);
            name=sb.toString();
        }
        int k=name.indexOf(' ')<0?POSIX.indexOf(name+" "):-1;
        if(k<0||k>0&&POSIX.charAt(k-1)!=' ')throw error("Unsupported character property {"+name+"} (only POSIX ASCII classes are implemented)");
        int idx=0;
        for(int i=0;i<k;i++)if(POSIX.charAt(i)==' ')idx++;
        int[] s=idx<POSIX_SETS.length?ci(set(POSIX_SETS[idx])):wide(ALL);
        if(p=='P') { supp=true; s=wide(not(s)); }
        return s;
    }
    private String groupname(int ch) {
        StringBuilder sb=new StringBuilder();
        if(!alpha(ch))throw error("capturing group name does not start with a Latin letter");
        do sb.append((char)ch); while(alpha(ch=read())||digit(ch));
        if(ch!='>')throw error("named capturing group is missing trailing '>'");
        return sb.toString();
    }
    private int[] clazz(boolean consume) {
        int[] prev=null, curr=null, bits=new int[0];
        boolean neg=false, hasBits=false;
        int ch=next();
        if(ch=='^'&&temp[cursor-1]=='[') { ch=next(); neg=true; }
        for(;;) {
            switch(ch) {
            case '[':
                curr=clazz(true);
                prev=prev==null?curr:or(prev,curr);
                ch=peek();
                continue;
            case '&':
                ch=next();
                if(ch=='&') {
                    ch=next();
                    int[] right=null;
                    while(ch!=']'&&ch!='&') {
                        int[] c;
                        if(ch=='[')c=clazz(true); else { unread(); c=clazz(false); }
                        right=right==null?c:or(right,c);
                        ch=peek();
                    }
                    if(hasBits) { if(prev==null)prev=curr=bits; else prev=or(prev,bits); hasBits=false; }
                    if(right!=null)curr=right;
                    if(prev==null) { if(right==null)throw error("Bad class syntax"); prev=right; }
                    else {
                        if(curr==null)throw error("Bad intersection syntax");
                        boolean w=isWide(prev)||isWide(curr);
                        prev=not(or(not(prev),not(curr)));
                        if(w)prev=wide(prev);
                    }
                    continue;
                }
                unread();
                break;
            case 0:
                if(cursor>=plen)throw error("Unclosed character class");
                break;
            case ']':
                if(prev!=null||hasBits) {
                    if(consume)next();
                    if(prev==null)prev=bits; else if(hasBits)prev=or(prev,bits);
                    return neg?wide(not(prev)):prev;
                }
            }
            int[] r=range();
            if(r==null) { hasBits=true; bits=or(bits,single(pred[0])); }
            else { curr=r; prev=prev==null?r:or(prev,r); }
            ch=peek();
        }
    }
    /** Parses one class item; returns null for a Latin-1 single (left in pred[0]) as the JDK's BitClass does. */
    private int[] range() {
        int ch=peek();
        if(ch=='\\') {
            ch=nextEscaped();
            if(ch=='p'||ch=='P')return family(ch);
            boolean isrange=temp[cursor+1]=='-';
            unread();
            ch=escape(true,true,isrange);
            if(ch==-1)return pred;
        } else next();
        if(peek()=='-') {
            int end=temp[cursor+1];
            if(end!='['&&end!=']') {
                next();
                int m=peek();
                if(m=='\\')m=escape(true,false,true); else next();
                if(m<ch)throw error("Illegal character range");
                return range(ch,m,true);
            }
        }
        if(ch<256) { pred=new int[]{ch}; return null; }
        return single(ch);
    }
    private int[] single(int c) { return range(c,c,false); }
    /** A range or single; marked non-BMP exactly where the JDK builds a non-BMP predicate. */
    private int[] range(int lo, int hi, boolean isRange) {
        int[] r=ci(new int[]{lo,hi});
        return isRange&&has(CASE_INSENSITIVE)||!(hi<0xd800||lo>0xdfff&&hi<0x10000)?wide(r):r;
    }
    /** ASCII case closure under CASE_INSENSITIVE. */
    private int[] ci(int[] s) {
        if(!has(CASE_INSENSITIVE))return s;
        int[] r=s;
        for(int i=0;i<s.length;i+=2)for(int base='A';base<='a';base+=32) {
            int lo=Math.max(s[i],base), hi=Math.min(s[i+1],base+25), d=base=='A'?32:-32;
            if(lo<=hi)r=or(r,new int[]{lo+d,hi+d});
        }
        return r;
    }
    private Node group0() {
        boolean capturing=false;
        Node head, tail;
        int save=flags0, saveTop=top.size();
        out=null;
        int ch=next();
        if(ch=='?') {
            ch=skip();
            switch(ch) {
            case ':':
                head=group(true); tail=out; head.next=expr(tail);
                break;
            case '=': case '!': case '>':
                head=group(true); tail=out; head.next=expr(tail);
                head=tail=ch=='>'?node(QUES,head,3,0):node(POS,head,ch=='!'?1:0,0);
                break;
            case '<':
                ch=read();
                if(ch!='='&&ch!='!') {
                    String name=groupname(ch);
                    if(names==null)names=new HashMap<>();
                    if(names.containsKey(name))throw error("Named capturing group <"+name+"> is already defined");
                    capturing=true;
                    head=group(false); tail=out;
                    names.put(name,groupCount-1);
                    head.next=expr(tail);
                    break;
                }
                head=group(true); tail=out; head.next=expr(tail);
                tail.next=new Node(LBEND);
                reset(); study(head);
                if(!svalid)throw error("Look-behind group does not have an obvious maximum length");
                head=tail=node(BEHIND,head,smax,smin);
                head.c=ch=='!'?1:0;
                clearTop(saveTop);
                break;
            case '$': case '@': throw error("Unknown group type");
            default:
                unread(); flag();
                ch=read();
                if(ch==')')return null;
                if(ch!=':')throw error("Unknown inline modifier");
                head=group(true); tail=out; head.next=expr(tail);
            }
        } else { capturing=true; head=group(false); tail=out; head.next=expr(tail); }
        if(read()!=')')throw error("Unclosed group");
        flags0=save;
        Node node=closure(head);
        if(node==head) { out=tail; return node; }
        if(head==tail) { out=node; return node; }
        clearTop(saveTop);
        if(node.t==QUES) {
            if(node.a==2) { out=node; return node; }
            Node conn=tail.next=new Node(CONN);
            head=node(BRANCH,conn,0,0);
            head.alts=node.a==0?new Node[]{node.atom,null}:new Node[]{null,node.atom};
            out=conn;
            return head;
        }
        if(node.c==2) { out=node; return node; }
        reset();
        if(study(head)) {
            Node g=node(GCURLY,head.next,node.a,node.b);
            g.c=node.c; g.d=tail.a; g.e=capturing?tail.b:0;
            out=g;
            return g;
        }
        Node loop=node(LOOP,head,node.a,node.b);
        loop.c=node.c; loop.d=localCount++; loop.e=head.a;
        if(node.c==0&&node.b==MAX)top.add(loop);
        tail.next=loop; out=loop;
        return node(PROLOG,loop,0,0);
    }
    private void clearTop(int n) { while(top.size()>n)top.remove(top.size()-1); }
    private Node group(boolean anonymous) {
        int local=localCount++;
        out=node(GTAIL,null,local,anonymous?0:2*groupCount++);
        return node(GHEAD,null,local,0);
    }
    private void flag() {
        int ch=peek();
        boolean sub=false;
        for(;;) {
            int f=ch=='i'?2:ch=='m'?8:ch=='s'?32:ch=='d'?1:ch=='x'?4:ch=='u'?64:ch=='c'?128:ch=='U'?320:0;
            if(f==0) { if(ch!='-'||sub)return; sub=true; }
            else if(sub)flags0&=~f;
            else { if(f>=64)throw error("Unsupported inline flag '"+(char)ch+"'"); flags0|=f; }
            ch=next();
        }
    }
    private int qtype() {
        int ch=next();
        if(ch=='?') { next(); return 1; }
        if(ch=='+') { next(); return 2; }
        return 0;
    }
    private Node curly(Node prev, int cmin, int cmax, int q) {
        if(q==0&&cmax==MAX&&prev.t==PROP) { Node g=node(GPROP,null,cmin,0); g.set=prev.set; return g; }
        Node c=node(CURLY,prev,cmin,cmax); c.c=q; return c;
    }
    private Node closure(Node prev) {
        int ch=peek();
        switch(ch) {
        case '?': return node(QUES,prev,qtype(),0);
        case '*': case '+': return curly(prev,ch=='*'?0:1,MAX,qtype());
        case '{':
            ch=skip();
            if(!digit(ch))throw error("Illegal repetition");
            long cmin=0, cmax;
            do { cmin=cmin*10+ch-'0'; if(cmin>MAX)throw error("Illegal repetition range"); } while(digit(ch=read()));
            if(ch==',') {
                ch=read();
                if(ch=='}') { unread(); return curly(prev,(int)cmin,MAX,qtype()); }
                cmax=0;
                while(digit(ch)) { cmax=cmax*10+ch-'0'; if(cmax>MAX)throw error("Illegal repetition range"); ch=read(); }
            } else cmax=cmin;
            if(ch!='}')throw error("Unclosed counted closure");
            if(cmax<cmin)throw error("Illegal repetition range");
            unread();
            if(cmin==0&&cmax==1)return node(QUES,prev,qtype(),0);
            Node c=node(CURLY,prev,(int)cmin,(int)cmax); c.c=qtype(); return c;
        default: return prev;
        }
    }

    // ---- study (TreeInfo) ----
    private void reset() { smin=smax=0; svalid=sdet=true; }
    private boolean study(Node n) {
        for(;;n=n.next) {
            if(n==null)return sdet;
            switch(n.t) {
            case LINE: smin++; smax+=2; break;
            case PROP: smin++; smax++; break;
            case QUES:
                if(n.a!=3) { int m=smin; study(n.atom); smin=m; sdet=false; } else study(n.atom);
                break;
            case GPROP: smin+=n.a; if(svalid)smax+=MAX; sdet=false; break;
            case CURLY: case GCURLY: {
                int m=smin, x=smax; boolean v=svalid, d=sdet;
                reset(); study(n.atom);
                int t=smin*n.a+m;
                smin=t<m?0xFFFFFFF:t;
                if(v&svalid) { t=smax*n.b+x; smax=t; if(t<x)svalid=false; } else svalid=false;
                sdet=sdet&&n.a==n.b&&d;
                break;
            }
            case CONN: return sdet;
            case BRANCH: {
                int m=smin, x=smax, m2=MAX, x2=-1; boolean v=svalid;
                for(Node a:n.alts) { reset(); if(a!=null)study(a); m2=Math.min(m2,smin); x2=Math.max(x2,smax); v&=svalid; }
                reset(); study(n.atom.next);
                smin+=m+m2; smax+=x+x2; svalid&=v; sdet=false;
                return false;
            }
            case PROLOG: case LOOP: svalid=sdet=false; return false;
            case BREF: svalid=false; break;
            }
        }
    }

    // ---- code point sets: sorted disjoint [lo,hi] pairs ----
    static int[] set(String s) { int[] r=new int[s.length()]; for(int i=0;i<r.length;i++)r[i]=s.charAt(i); return r; }
    static int[] or(int[] a, int[] b) {
        int n=a.length+b.length, k=0;
        int[] r=Arrays.copyOf(a,n);
        System.arraycopy(b,0,r,a.length,b.length);
        for(int i=2;i<n;i+=2) {
            int lo=r[i], hi=r[i+1], j=i;
            for(;j>0&&r[j-2]>lo;j-=2) { r[j]=r[j-2]; r[j+1]=r[j-1]; }
            r[j]=lo; r[j+1]=hi;
        }
        for(int i=0;i<n;i+=2) {
            if(k>0&&r[i]<=r[k-1]+1) { if(r[i+1]>r[k-1])r[k-1]=r[i+1]; }
            else { r[k++]=r[i]; r[k++]=r[i+1]; }
        }
        return Arrays.copyOf(r,k);
    }
    /** Complement within the code points (drops the non-BMP marker). */
    static int[] not(int[] a) {
        int[] r=new int[a.length+2];
        int k=0, p=0;
        for(int i=0;i<a.length&&a[i]<=0x10ffff;i+=2) { if(a[i]>p) { r[k++]=p; r[k++]=a[i]-1; } p=Math.min(a[i+1],0x10ffff)+1; }
        if(p<=0x10ffff) { r[k++]=p; r[k++]=0x10ffff; }
        return Arrays.copyOf(r,k);
    }
    static boolean in(int[] s, int c) {
        for(int i=0;i<s.length;i+=2) { if(c<s[i])return false; if(c<=s[i+1])return true; }
        return false;
    }
    /** Sets from non-BMP JDK predicates carry a marker pair above U+10FFFF; it selects the surrogate-aware search loop. */
    static int[] wide(int[] s) { int n=s.length; int[] r=Arrays.copyOf(s,n+2); r[n]=r[n+1]=0x110000; return r; }
    static boolean isWide(int[] s) { return s.length>0&&s[s.length-1]>0x10ffff; }
}
