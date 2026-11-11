package java.util.regex;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;
import java.util.regex.Pattern.Node;

/** Matcher state plus the backtracking interpreter for {@link Pattern}'s node graph. */
public final class Matcher implements MatchResult {
    private Pattern p;
    private CharSequence text;
    private int[] groups, locals;
    private int[][] memo;
    private int from, to, lbt, mode, first=-1, last, oldLast=-1, append;
    private boolean hitEnd, requireEnd;

    Matcher(Pattern p, CharSequence text) { this.text=text; usePattern(p); reset(); }
    public Pattern pattern() { return p; }
    public Matcher usePattern(Pattern np) {
        if(np==null)throw new IllegalArgumentException("Pattern cannot be null");
        p=np;
        groups=new int[Math.max(np.groupCount,10)*2];
        locals=new int[np.localCount];
        java.util.Arrays.fill(groups,-1); java.util.Arrays.fill(locals,-1);
        memo=new int[np.posCount][];
        return this;
    }
    public MatchResult toMatchResult() {
        Matcher r=new Matcher(p,first<0?"":text.toString());
        r.first=first; r.last=last; r.groups=groups.clone();
        return r;
    }
    public Matcher reset() {
        first=-1; last=0; oldLast=-1; append=0;
        java.util.Arrays.fill(groups,-1); java.util.Arrays.fill(locals,-1);
        memo=new int[p.posCount][];
        from=0; to=text.length();
        return this;
    }
    public Matcher reset(CharSequence input) { text=input; return reset(); }
    public Matcher region(int start, int end) {
        int n=text.length();
        if(start<0||start>n)throw new IndexOutOfBoundsException("start");
        if(end<0||end>n)throw new IndexOutOfBoundsException("end");
        if(start>end)throw new IndexOutOfBoundsException("start > end");
        reset(); from=start; to=end;
        return this;
    }
    public int regionStart() { return from; }
    public int regionEnd() { return to; }
    public boolean hitEnd() { return hitEnd; }
    public boolean requireEnd() { return requireEnd; }
    public boolean hasMatch() { return first>=0; }
    public int groupCount() { return p.groupCount-1; }
    public Map<String,Integer> namedGroups() { return p.namedGroups(); }
    private void check(int g) {
        if(first<0)throw new IllegalStateException("No match found");
        if(g<0||g>groupCount())throw new IndexOutOfBoundsException("No group "+g);
    }
    private int named(String name) {
        Objects.requireNonNull(name,"Group name");
        check(0);
        Integer n=p.names==null?null:p.names.get(name);
        if(n==null)throw new IllegalArgumentException("No group with name <"+name+">");
        return n;
    }
    public int start() { check(0); return first; }
    public int start(int g) { check(g); return groups[g*2]; }
    public int start(String name) { return groups[named(name)*2]; }
    public int end() { check(0); return last; }
    public int end(int g) { check(g); return groups[g*2+1]; }
    public int end(String name) { return groups[named(name)*2+1]; }
    public String group() { return group(0); }
    public String group(int g) { check(g); return sub(g); }
    public String group(String name) { return sub(named(name)); }
    private String sub(int g) {
        int s=groups[g*2], e=groups[g*2+1];
        return s<0||e<0?null:text.subSequence(s,e).toString();
    }
    public boolean matches() { return run(from,2); }
    public boolean lookingAt() { return run(from,1); }
    public boolean find() {
        int n=last;
        if(n==first)n++;
        if(n<from)n=from;
        if(n>to) { java.util.Arrays.fill(groups,-1); return false; }
        return run(n,0);
    }
    public boolean find(int start) {
        if(start<0||start>text.length())throw new IndexOutOfBoundsException("Illegal start index");
        reset();
        return run(start,0);
    }
    private boolean run(int f, int m) {
        hitEnd=requireEnd=false;
        if(f<0)f=0;
        first=f;
        if(oldLast<0)oldLast=f;
        java.util.Arrays.fill(groups,-1);
        memo=new int[p.posCount][];
        mode=m;
        boolean r=match(m==0?p.root:p.matchRoot,f);
        if(!r)first=-1;
        oldLast=last;
        return r;
    }
    public static String quoteReplacement(String s) {
        StringBuilder sb=new StringBuilder();
        for(int i=0;i<s.length();i++) { char c=s.charAt(i); if(c=='\\'||c=='$')sb.append('\\'); sb.append(c); }
        return sb.toString();
    }
    public Matcher appendReplacement(StringBuilder sb, String replacement) {
        check(0);
        int len=sb.length();
        try {
            sb.append(text,append,first);
            expand(sb,replacement);
        } catch(IllegalArgumentException e) { sb.setLength(len); throw e; }
        append=last;
        return this;
    }
    private void expand(StringBuilder sb, String r) {
        for(int i=0, n=r.length();i<n;) {
            char c=r.charAt(i++);
            if(c=='\\') {
                if(i==n)throw new IllegalArgumentException("character to be escaped is missing");
                sb.append(r.charAt(i++));
            } else if(c!='$')sb.append(c);
            else {
                if(i==n)throw new IllegalArgumentException("Illegal group reference: group index is missing");
                c=r.charAt(i);
                int ref;
                if(c=='{') {
                    int begin=++i;
                    while(i<n&&((c=r.charAt(i))>='a'&&c<='z'||c>='A'&&c<='Z'||c>='0'&&c<='9'))i++;
                    if(begin==i)throw new IllegalArgumentException("named capturing group has 0 length name");
                    if(c!='}')throw new IllegalArgumentException("named capturing group is missing trailing '}'");
                    String name=r.substring(begin,i++);
                    if(name.charAt(0)<='9')throw new IllegalArgumentException("capturing group name {"+name+"} starts with digit character");
                    Integer g=p.names==null?null:p.names.get(name);
                    if(g==null)throw new IllegalArgumentException("No group with name {"+name+"}");
                    ref=g;
                } else {
                    ref=c-'0';
                    if(ref<0||ref>9)throw new IllegalArgumentException("Illegal group reference");
                    for(i++;i<n;i++) {
                        int d=r.charAt(i)-'0';
                        if(d<0||d>9||groupCount()<ref*10+d)break;
                        ref=ref*10+d;
                    }
                }
                if(start(ref)!=-1&&end(ref)!=-1)sb.append(text,start(ref),end(ref));
            }
        }
    }
    public StringBuilder appendTail(StringBuilder sb) { return sb.append(text,append,text.length()); }
    public String replaceAll(String replacement) { return replace(replacement,true); }
    public String replaceAll(Function<MatchResult,String> replacer) { return replace(Objects.requireNonNull(replacer),true); }
    public String replaceFirst(String replacement) { return replace(Objects.requireNonNull(replacement,"replacement"),false); }
    public String replaceFirst(Function<MatchResult,String> replacer) { return replace(Objects.requireNonNull(replacer),false); }
    @SuppressWarnings("unchecked")
    private String replace(Object r, boolean all) {
        reset();
        if(!find())return text.toString();
        StringBuilder sb=new StringBuilder();
        do appendReplacement(sb,r instanceof String?(String)r:((Function<MatchResult,String>)r).apply(this)); while(all&&find());
        return appendTail(sb).toString();
    }
    public String toString() {
        return "java.util.regex.Matcher[pattern="+p+" region="+from+","+to+" lastmatch="+(first>=0&&group()!=null?group():"")+"]";
    }

    // ---- interpreter ----
    private int cp(int i) {
        char c=text.charAt(i);
        if(Character.isHighSurrogate(c)&&i+1<text.length()) { char d=text.charAt(i+1); if(Character.isLowSurrogate(d))return Character.toCodePoint(c,d); }
        return c;
    }
    private static boolean word(int c) { return c=='_'||c<128&&(c>='0'&&c<='9'||(c|32)>='a'&&(c|32)<='z'); }
    private boolean match(Node n, int i) {
        for(;;n=n.next) {
            switch(n.t) {
            case Pattern.ACC: case Pattern.LASTN:
                if(n.t==Pattern.LASTN&&mode==2&&i!=to)return false;
                last=i; groups[0]=first; groups[1]=i;
                return true;
            case Pattern.START: {
                int g=to-n.a;
                for(;i<=g;i++) {
                    if(match(n.next,i)) { first=i; groups[0]=i; groups[1]=last; return true; }
                    if(i<g&&n.b!=0&&Character.isHighSurrogate(text.charAt(i))&&i+1<text.length()&&Character.isLowSurrogate(text.charAt(i+1)))i++;
                }
                hitEnd=true;
                return false;
            }
            case Pattern.BEGIN:
                if(i==from&&match(n.next,i)) { first=i; groups[0]=i; groups[1]=last; return true; }
                return false;
            case Pattern.END:
                if(i!=to)return false;
                hitEnd=true;
                break;
            case Pattern.CARET:
                if(i==to) { hitEnd=true; return false; }
                if(i>from) {
                    char c=text.charAt(i-1);
                    if(n.a!=0?c!='\n':c!='\n'&&c!='\r'&&(c|1)!=0x2029&&c!=0x85||c=='\r'&&text.charAt(i)=='\n')return false;
                }
                break;
            case Pattern.LASTM:
                if(i!=oldLast)return false;
                break;
            case Pattern.DOLLAR: {
                boolean multi=n.a!=0;
                if(n.b!=0) {
                    if(i<to) { if(text.charAt(i)!='\n'||!multi&&i!=to-1)return false; if(multi)break; }
                } else {
                    if(!multi) {
                        if(i<to-2)return false;
                        if(i==to-2&&(text.charAt(i)!='\r'||text.charAt(i+1)!='\n'))return false;
                    }
                    if(i<to) {
                        char c=text.charAt(i);
                        if(c=='\n') { if(i>0&&text.charAt(i-1)=='\r')return false; if(multi)break; }
                        else if(c=='\r'||c==0x85||(c|1)==0x2029) { if(multi)break; }
                        else return false;
                    }
                }
                hitEnd=requireEnd=true;
                break;
            }
            case Pattern.LINE:
                if(i>=to) { hitEnd=true; return false; }
                int ch=text.charAt(i++);
                if(ch==13) {
                    if(i<to) { if(text.charAt(i)==10&&match(n.next,i+1))return true; } else hitEnd=true;
                } else if(!(ch>=10&&ch<=12||ch==0x85||ch==0x2028||ch==0x2029))return false;
                break;
            case Pattern.PROP:
                if(i<to) {
                    int c=cp(i), k=i+Character.charCount(c);
                    if(k<=to) { if(!Pattern.in(n.set,c))return false; i=k; break; }
                }
                hitEnd=true;
                return false;
            case Pattern.QUES:
                switch(n.a) {
                case 0: return match(n.atom,i)&&match(n.next,last)||match(n.next,i);
                case 1: return match(n.next,i)||match(n.atom,i)&&match(n.next,last);
                case 2: if(match(n.atom,i))i=last; break;
                default: if(!match(n.atom,i))return false; i=last;
                }
                break;
            case Pattern.GPROP: {
                int s=i, count=0;
                while(i<to) {
                    int c=cp(i), l=Character.charCount(c);
                    if(i+l>to) { hitEnd=true; c=text.charAt(i); l=1; }
                    if(!Pattern.in(n.set,c))break;
                    i+=l; count++;
                }
                if(i>=to)hitEnd=true;
                for(;count>=n.a;count--) {
                    if(match(n.next,i))return true;
                    i=Math.max(s,i-(i>=2&&Character.isLowSurrogate(text.charAt(i-1))&&Character.isHighSurrogate(text.charAt(i-2))?2:1));
                }
                return false;
            }
            case Pattern.CURLY: {
                int j=0;
                for(;j<n.a;j++) { if(!match(n.atom,i))return false; i=last; }
                if(n.c==0)return curly0(n,i,j);
                for(;;) {
                    if(n.c==1&&match(n.next,i))return true;
                    if(j>=n.b)return n.c==2&&match(n.next,i);
                    if(!match(n.atom,i)||i==last)return n.c==2&&match(n.next,i);
                    i=last; j++;
                }
            }
            case Pattern.GCURLY: {
                int g=n.e, l=n.d, s0=locals[l], s1=groups[g], s2=groups[g+1];
                locals[l]=-1;
                boolean r=true;
                for(int j=0;j<n.a;j++) {
                    if(!match(n.atom,i)) { r=false; break; }
                    if(g!=0) { groups[g]=i; groups[g+1]=last; }
                    i=last;
                }
                if(r)r=n.c==0?gcurly0(n,i,n.a):gcurly1(n,i,n.a);
                if(!r) { locals[l]=s0; if(g!=0) { groups[g]=s1; groups[g+1]=s2; } }
                return r;
            }
            case Pattern.CONN: case Pattern.EMPTY:
                break;
            case Pattern.BRANCH:
                for(Node a:n.alts)if(match(a==null?n.atom.next:a,i))return true;
                return false;
            case Pattern.GHEAD: {
                int s=locals[n.a];
                locals[n.a]=i;
                boolean r=match(n.next,i);
                locals[n.a]=s;
                return r;
            }
            case Pattern.GTAIL: {
                int t=locals[n.a];
                if(t<0) { last=i; return true; }
                int g=n.b, s=groups[g], e=groups[g+1];
                groups[g]=t; groups[g+1]=i;
                if(match(n.next,i))return true;
                groups[g]=s; groups[g+1]=e;
                return false;
            }
            case Pattern.PROLOG: {
                Node L=n.atom;
                int save=locals[L.d];
                boolean r;
                if(L.f>=0&&memo[L.f]==null)memo[L.f]=new int[(text.length()>>5)+1];
                if(0<L.a) { locals[L.d]=1; r=match(L.atom,i); }
                else if(L.c!=0&&match(L.next,i))r=true;
                else if(0<L.b) { locals[L.d]=1; r=match(L.atom,i)||L.c==0&&match(L.next,i); }
                else r=L.c==0&&match(L.next,i);
                locals[L.d]=save;
                return r;
            }
            case Pattern.LOOP:
                if(i>locals[n.e]) {
                    int c=locals[n.d];
                    if(c<n.a) {
                        locals[n.d]=c+1;
                        if(match(n.atom,i))return true;
                        locals[n.d]=c;
                        return false;
                    }
                    if(n.c!=0) {
                        if(match(n.next,i))return true;
                        if(c>=n.b)return false;
                        locals[n.d]=c+1;
                        if(match(n.atom,i))return true;
                        locals[n.d]=c;
                        return false;
                    }
                    if(c<n.b) {
                        int[] m=n.f>=0?memo[n.f]:null;
                        if(m!=null&&(m[i>>5]>>>i&1)!=0)break;
                        locals[n.d]=c+1;
                        if(match(n.atom,i))return true;
                        locals[n.d]=c;
                        if(m!=null)m[i>>5]|=1<<i;
                    }
                }
                break;
            case Pattern.BREF: {
                int j=groups[n.a], k=groups[n.a+1], size=k-j;
                if(j<0)return false;
                if(i+size>to) { hitEnd=true; return false; }
                for(int x=0;x<size;x++) {
                    int a=text.charAt(i+x), b=text.charAt(j+x);
                    if(a!=b&&(n.b==0||lower(a)!=lower(b)))return false;
                }
                i+=size;
                break;
            }
            case Pattern.POS:
                if(n.a!=0&&i>=to)requireEnd=true;
                if(match(n.atom,i)==(n.a!=0))return false;
                break;
            case Pattern.BEHIND: {
                int lo=Math.max(i-n.a,from), saved=lbt;
                boolean r=false;
                lbt=i;
                for(int j=i-n.b;!r&&j>=lo;j--)r=match(n.atom,j);
                lbt=saved;
                if(r==(n.c!=0))return false;
                break;
            }
            case Pattern.LBEND:
                return i==lbt;
            case Pattern.BOUND: {
                boolean left=i>from&&word(text.charAt(i-1)), right=false;
                if(i<to)right=word(text.charAt(i)); else hitEnd=requireEnd=true;
                if(((left^right?right?1:2:4)&n.a)==0)return false;
                break;
            }
            }
        }
    }
    private static int lower(int c) { return c>='A'&&c<='Z'?c+32:c; }
    private boolean curly0(Node n, int i, int j) {
        if(j>=n.b)return match(n.next,i);
        int back=j;
        if(match(n.atom,i)) {
            int k=last-i;
            if(k!=0) {
                i=last; j++;
                while(j<n.b&&match(n.atom,i)) {
                    if(i+k!=last) { if(curly0(n,last,j+1))return true; break; }
                    i+=k; j++;
                }
                for(;j>=back;j--,i-=k)if(match(n.next,i))return true;
                return false;
            }
        }
        return match(n.next,i);
    }
    private boolean gcurly0(Node n, int i, int j) {
        int min=j, g=n.e, s0=groups[g], s1=groups[g+1];
        if(j<n.b&&match(n.atom,i)) {
            int k=last-i;
            if(k<=0) {
                if(g!=0) { groups[g]=i; groups[g+1]=i+k; }
                i+=k;
            } else {
                for(;;) {
                    if(g!=0) { groups[g]=i; groups[g+1]=i+k; }
                    i+=k;
                    if(++j>=n.b||!match(n.atom,i))break;
                    if(i+k!=last) { if(gcurly0(n,i,j))return true; break; }
                }
                for(;j>min;j--) {
                    if(match(n.next,i)) { if(g!=0) { groups[g+1]=i; groups[g]=i-k; } return true; }
                    i-=k;
                    if(g!=0) { groups[g+1]=i; groups[g]=i-k; }
                }
            }
        }
        if(g!=0) { groups[g]=s0; groups[g+1]=s1; }
        return match(n.next,i);
    }
    private boolean gcurly1(Node n, int i, int j) {
        int g=n.e;
        for(;;) {
            if(n.c==1&&match(n.next,i))return true;
            if(j>=n.b)return n.c==2&&match(n.next,i);
            if(!match(n.atom,i))return n.c==2&&match(n.next,i);
            if(n.c==1&&i==last)return false;
            if(g!=0) { groups[g]=i; groups[g+1]=last; }
            if(i==last)return match(n.next,i);
            i=last; j++;
        }
    }
}
