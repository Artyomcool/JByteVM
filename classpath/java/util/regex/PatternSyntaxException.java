package java.util.regex;
public class PatternSyntaxException extends IllegalArgumentException {
    private final String desc, pattern;
    private final int index;
    public PatternSyntaxException(String desc, String regex, int index) { this.desc=desc; pattern=regex; this.index=index; }
    public int getIndex() { return index; }
    public String getDescription() { return desc; }
    public String getPattern() { return pattern; }
    public String getMessage() {
        String nl=System.lineSeparator();
        StringBuilder sb=new StringBuilder().append(desc);
        if(index>=0)sb.append(" near index ").append(index);
        sb.append(nl).append(pattern);
        if(index>=0&&pattern!=null&&index<pattern.length()) {
            sb.append(nl);
            for(int i=0;i<index;i++)sb.append(pattern.charAt(i)=='\t'?'\t':' ');
            sb.append('^');
        }
        return sb.toString();
    }
}
