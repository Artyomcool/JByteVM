import java.util.*;
import java.util.regex.*;

/** java.util.regex and String.format scenarios hashed for HotSpot comparison (the oracle runs with an en-US locale). */
public class TextValues {
    static int h;
    static void mix(int v){h=h*31+v;}
    static void mix(String s){mix(s==null?7:s.hashCode());}
    static void mix(boolean b){mix(b?1:0);}
    static void fail(Runnable r){try{r.run();mix(0);}catch(RuntimeException e){mix(e.getClass().getName());mix(e.getMessage());}}
    static String text(Random r,int n,String alphabet){StringBuilder sb=new StringBuilder();for(int i=0;i<n;i++)sb.append(alphabet.charAt(r.nextInt(alphabet.length())));return sb.toString();}
    static void matches(Pattern p,String s){
        Matcher m=p.matcher(s);
        mix(m.matches());mix(m.lookingAt());m.reset();
        while(m.find()){for(int g=0;g<=m.groupCount();g++){mix(m.start(g));mix(m.end(g));mix(m.group(g));}}
        mix(Arrays.toString(p.split(s)));mix(Arrays.toString(p.split(s,-1)));mix(Arrays.toString(p.split(s,2)));
    }

    static final String[] PATTERNS={"a+b*","(a|ab)(c|bcd)(d*)","^(\\w+)\\s*=\\s*(.*)$","\\b\\w","\\B","x*","(?i)hello|WORLD","[^a-c]+","(\\d{1,3})(?:,(\\d{3}))*",
        "(a*)+b","(a|b)*?c","((a)|b)+","(?<word>[A-Za-z]+)-\\k<word>","(\\w)\\1","(?m)^\\s*#.*$","(?s)<.+?>","a{2,3}+a","(?=a)\\w","(?<=\\$)\\d+(?!\\.)","(?>a+)b|ab",
        "\\Qa.b\\E|[.]","[a-z&&[^aeiou]]+","\\p{Punct}|\\p{Upper}","(x(\\w))*x\\w","(?x) a \\  b # comment\n | c","$","\\R","[\\t-\\r ]+","(?:)","\\G\\w"};
    public static int patterns(int seed){
        h=seed;Random r=new Random(seed);
        for(String re:PATTERNS){
            Pattern p=Pattern.compile(re);mix(p.pattern());mix(p.flags());
            for(int i=0;i<6;i++)matches(p,text(r,r.nextInt(18),"aabbcdxX $.,#=-_1\n\r\tHelloWORLD"));
            matches(p,"key = value\n  # note\nhello world 1,234,567 $12 abab aa-aa <a>x</a>");
        }
        return h;
    }

    public static int flags(int seed){
        h=seed;Random r=new Random(seed);
        int[] flags={0,Pattern.CASE_INSENSITIVE,Pattern.MULTILINE,Pattern.DOTALL,Pattern.CASE_INSENSITIVE|Pattern.MULTILINE,Pattern.LITERAL,Pattern.COMMENTS,Pattern.UNIX_LINES};
        String[] res={"^ab.$","[A-C]+","a.b","(?-i)a(?i)b","A b","[^x]$","\\w+$",".+"};
        for(int f:flags)for(String re:res){
            Pattern p=Pattern.compile(re,f);mix(p.flags());
            for(int i=0;i<4;i++)matches(p,text(r,r.nextInt(12),"aAbBcCx\n\r .+$^"));
        }
        return h;
    }

    public static int replace(int seed){
        h=seed;Random r=new Random(seed);
        Pattern p=Pattern.compile("(?<key>\\w+)=(\\d*)");
        String s="a=1, bb=22, ccc=, d="+seed;
        mix(p.matcher(s).replaceAll("$2:${key}"));mix(p.matcher(s).replaceFirst("[$0]"));mix(p.matcher(s).replaceAll("\\$1\\\\"));
        mix(p.matcher(s).replaceAll(m->m.group(1).toUpperCase()+m.end()));
        mix(Pattern.compile("x*").matcher("abc").replaceAll("-"));mix(Pattern.compile("").matcher("ab").replaceAll("/"));
        mix(Matcher.quoteReplacement("a$b\\c"));mix(Pattern.quote("a\\Eb.c"));mix(Pattern.matches(Pattern.quote("a\\Eb.c"),"a\\Eb.c"));
        Matcher m=p.matcher(s);StringBuilder sb=new StringBuilder();
        while(m.find()){m.appendReplacement(sb,m.group(2).isEmpty()?"<$1>":"$2$2");mix(m.start("key"));mix(m.end(2));mix(m.group("key"));}
        mix(m.appendTail(sb).toString());
        fail(()->p.matcher(s).replaceAll("$3"));fail(()->p.matcher(s).replaceAll("${nope}"));fail(()->p.matcher(s).replaceAll("x\\"));
        fail(()->p.matcher(s).replaceAll("$"));fail(()->p.matcher(s).group());fail(()->{Matcher q=p.matcher(s);q.find();q.group(3);});
        fail(()->{Matcher q=p.matcher(s);q.find();q.group("x");});fail(()->p.matcher(s).find(-1));
        Matcher mm=p.matcher(s);mix(mm.find(8));mix(mm.start());mix(mm.find());mix(mm.toString());mm.region(3,14);mix(mm.find());fail(()->mix(mm.group()));mix(mm.regionEnd());
        MatchResult mr=mm.toMatchResult();fail(()->mix(mr.group(1)));fail(()->mix(mr.start()));mm.reset("z=9");mix(mm.matches());mix(mr.groupCount());mix(mm.hitEnd());mix(mm.end(2));
        mix(mm.usePattern(Pattern.compile("\\d")).find(0));mix(mm.group());mix(mm.groupCount());
        Matcher m2=Pattern.compile("(b+)").matcher("abbbc");m2.find();MatchResult r2=m2.toMatchResult();mix(r2.group(1));mix(r2.end());mix(m2.find());mix(r2.start(1));
        for(int i=0;i<20;i++){String t=text(r,r.nextInt(12),"ab ,;");mix(Arrays.toString(Pattern.compile("[,;]\\s*|\\s+").split(t,i%4-1)));}
        mix(Arrays.toString(Pattern.compile(",").split(",a,,b,,")));mix(Arrays.toString(Pattern.compile("").split("abc")));
        mix(Arrays.toString(Pattern.compile("(?=b)").split("abab")));mix(Arrays.toString(Pattern.compile(",").splitWithDelimiters("a,b,,c",0)));
        return h;
    }

    public static int errors(int seed){
        h=seed;
        String[] bad={"(","a)","[a-","*a","a{2,1}","x{","[z-a]","(?<n>a)(?<n>b)","\\","\\k<q>","(?<=a+)b","\\p{Foo}","a**","(?z)","[\\d-z]","\\xZ","\\u12","{,3}","a{99999999999}","[&&]"};
        for(String b:bad){
            try{Pattern.compile(b);mix(1);}
            catch(PatternSyntaxException e){mix(e.getIndex());mix(e.getPattern());mix(b.startsWith("\\p")?0:e.getDescription().hashCode());}
        }
        try{Pattern.compile("ab(c");}catch(PatternSyntaxException e){mix(e.getMessage());}
        return h;
    }

    static final Object[] VALUES={0,-1,42,Integer.MIN_VALUE,Long.MAX_VALUE,Long.MIN_VALUE,(short)-300,(byte)-7,(byte)100,'x','\u00e9',"text",null,true,false,
        0.0,-0.0,1.5,-2.25,0.125,0.15,1e-5,123456.789,9.995,1e22,Double.MAX_VALUE,Double.MIN_VALUE,Double.NaN,Double.NEGATIVE_INFINITY,1.1f,-3.4e38f,(float)1e-40};
    static final String[] SPECS={"%s","%S","%10s","%-10s|","%.3s","%d","%,d","%+d","% d","%(d","%08d","%-8d|","%x","%X","%#x","%o","%#o","%08X","%c","%C","%b","%B","%h",
        "%e","%.0e","%.10E","%f","%.0f","%.1f","%.3f","%,.2f","%+.4f","%(.2f","%015.3f","%-12.2f|","%#.0f","%g","%.0g","%.3g","%G","%,g","%a","%.2a","%A","%#.0e"};
    public static int format(int seed){
        h=seed;Random r=new Random(seed);
        for(String spec:SPECS)for(Object v:VALUES){
            Object[] a={v};
            try{mix(String.format(spec,a));}catch(RuntimeException e){mix(e.getClass().getName());mix(e.getMessage());}
        }
        mix(String.format("%2$s %1$s %<s %s %s","a","b"));mix(String.format("%%%n%5%|%-5%|"));mix(String.format("x"));
        mix(String.format("%s %s",(Object[])null));mix("%d-%s".formatted(seed,"z"));
        String[] bad={"%","%q","%-d","%+ d","%#d","%.2d","%,x","%#b","%5n","%-n","%-%","%0s","%3$s","%<s","%0$s","%.2c","%ty","%tq","%-5.f","%--s","%999999999999d"};
        for(String b:bad)fail(()->String.format(b,1,2));
        fail(()->String.format("%c",-5));fail(()->String.format("%c",0x110000));fail(()->String.format("%d","s"));fail(()->String.format("%f",1));
        for(int i=0;i<200;i++){
            double d=i%3==0?Double.longBitsToDouble(r.nextLong()):(r.nextInt(2000001)-1000000)/Math.pow(10,r.nextInt(9));
            int p=r.nextInt(12);
            mix(String.format("%."+p+"f|%."+p+"e|%."+p+"g|%,."+p+"f|%."+(p+1)+"a",d,d,d,d,d));
        }
        return h;
    }
}
