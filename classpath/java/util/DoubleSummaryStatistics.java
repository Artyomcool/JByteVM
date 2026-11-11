package java.util;
import java.util.function.DoubleConsumer;
/** Compensated (Kahan) summation as in the JDK, so sums and averages match bit for bit. */
public class DoubleSummaryStatistics implements DoubleConsumer {
    private long count; private double sum,compensation,simpleSum,min=Double.POSITIVE_INFINITY,max=Double.NEGATIVE_INFINITY;
    public DoubleSummaryStatistics(){}
    public DoubleSummaryStatistics(long count,double min,double max,double sum){
        if(count<0)throw new IllegalArgumentException("Negative count value");
        if(count>0){if(min>max)throw new IllegalArgumentException("Minimum greater than maximum");
            this.count=count;this.sum=sum;this.simpleSum=sum;this.min=min;this.max=max;}}
    public void accept(double v){++count;simpleSum+=v;add(v);min=Math.min(min,v);max=Math.max(max,v);}
    public void combine(DoubleSummaryStatistics o){count+=o.count;simpleSum+=o.simpleSum;add(o.sum);add(-o.compensation);min=Math.min(min,o.min);max=Math.max(max,o.max);}
    private void add(double v){double t=v-compensation,s=sum,velvel=s+t;compensation=(velvel-s)-t;sum=velvel;}
    public final long getCount(){return count;}
    public final double getSum(){double t=sum-compensation;return Double.isNaN(t)&&Double.isInfinite(simpleSum)?simpleSum:t;}
    public final double getMin(){return min;}
    public final double getMax(){return max;}
    public final double getAverage(){return getCount()>0?getSum()/getCount():0.0d;}
    public String toString(){return String.format("%s{count=%d, sum=%f, min=%f, average=%f, max=%f}","DoubleSummaryStatistics",getCount(),getSum(),getMin(),getAverage(),getMax());}
}
