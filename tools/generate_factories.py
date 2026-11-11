"""Emit Java List/Set/Map.of fixed-arity descriptors used by ordinary javac."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'classpath/java/util'
def generate():
    for name in ['List','Set','Map']:
        p=ROOT/(name+'.java');text=p.read_text();start='    // BEGIN GENERATED FACTORIES';end='    // END GENERATED FACTORIES'
        if start not in text:text=text.rsplit('}',1)[0]+start+'\n'+end+'\n}\n'
        lines=[]
        for n in range(11):
            if name=='Map':
                args=','.join(f'K k{i},V v{i}' for i in range(n));entries=','.join(f'entry(k{i},v{i})' for i in range(n))
                lines.append(f'    static <K,V> Map<K,V> of({args}){{return ofEntries({entries});}}')
            else:
                args=','.join(f'E e{i}' for i in range(n));entries=','.join(f'e{i}' for i in range(n))
                lines.append(f'    static <E> {name}<E> of({args}){{return jbv.runtime.Collections.immutable{name}(new Object[]{{{entries}}});}}')
        content=text.split(start)[0]+start+'\n'+'\n'.join(lines)+'\n'+end+text.split(end)[1]
        if text!=content:p.write_text(content)
if __name__=='__main__':generate()
