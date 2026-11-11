"""Record host allocator bytes separately from Java object heap bytes."""
import ctypes as C
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tests'))
from test_vm import VM, LIB, BUILD, CLASSES, FEATURES, OK, HeapStats
from test_memory import MemoryStats

LIB.jbv_new_array.argtypes=[C.c_void_p,C.c_char_p,C.c_int32,C.POINTER(C.c_int32)]
def snapshot(vm):
    stats=HeapStats();assert LIB.jbv_heap_stats(vm.handle,C.byref(stats))==OK
    memory=MemoryStats();assert LIB.jbv_memory_stats(vm.handle,C.byref(memory))==OK
    assert memory.used==sum(vm.live.values()) and memory.peak==vm.peak_bytes
    return dict(host_live_bytes=sum(vm.live.values()),host_live_allocations=len(vm.live),
                java_heap_bytes=stats.bytes,java_objects=stats.objects,
                memory_peak_bytes=memory.peak,memory_limit_bytes=memory.limit)

report={}
for slots in (0,2048):
    with VM(slots=slots) as vm:
        assert vm.status==OK
        report['startup_'+str(slots or 16384)+'_slots']=snapshot(vm)
with VM() as vm:
    report['arrays']={}
    for descriptor in (b'[C',b'[I'):
        ref=C.c_int32();before=snapshot(vm)
        assert LIB.jbv_new_array(vm.handle,descriptor,1024,C.byref(ref))==OK
        report['arrays'][descriptor.decode()]=snapshot(vm)['java_heap_bytes']-before['java_heap_bytes']
        assert LIB.jbv_release(vm.handle,ref)==OK
        assert LIB.jbv_collect(vm.handle)==OK
if FEATURES&16:
    with VM(instructions=50000000) as vm:
        for path in sorted(CLASSES.glob('CollectionValues*.class')):assert vm.load(path.read_bytes())==OK
        report['collections_loaded']=snapshot(vm)
        for method in ('list','views','map','functions','factories','sets','errors'):
            assert vm.call(method,17,owner='CollectionValues')[0]==OK
        assert LIB.jbv_collect(vm.handle)==OK
        report['collections_initialized_after_gc']=snapshot(vm)
    with VM(instructions=20000000) as vm:
        for path in sorted(CLASSES.rglob('*.class')):
            if path.name.startswith('Reflection') or path.parent.name=='reflection':assert vm.load(path.read_bytes())==OK
        report['reflection_loaded']=snapshot(vm)
        for owner,method,n in [('ReflectionValues','churn',300),('ReflectionAnnotations','values',0),('ReflectionAnnotations','members',0),('ReflectionAnnotations','equality',30)]:
            assert vm.call(method,n,owner=owner)[0]==OK
        assert LIB.jbv_collect(vm.handle)==OK
        report['reflection_initialized_after_gc']=snapshot(vm)
(BUILD/'ram-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
