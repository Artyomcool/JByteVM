"""Generate src/interp_x86.asm: the hot bytecodes of jbv_execute as a threaded x86
interpreter core, in the manner of HotSpot's template interpreter.

  python tools/gen_interp_x86.py      # rewrites src/interp_x86.asm

Registers: esi bytecode pointer, edi locals (the operand stack follows them, sp counts
from locals), ebx sp, ebp reference bits, eax top of stack (write-through: memory always
holds every slot, eax is a copy of the top), ecx/edx scratch. Every handler ends with
its own dispatch. An opcode the core does not run, or any condition it does not handle
(null, bounds, unresolved constant, exhausted budget), returns to C at that opcode,
which executes it completely and calls the core again; the C loop alone is a complete
interpreter. Layout constants are checked by static asserts in interpreter.c."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONSTANT_SIZE, CONSTANT_BITS, CONSTANT_LINK = 24, 8, 16      # JbvConstant: size, bits, text.data
LINK_SLOT, LINK_KIND, LINK_TYPE, LINK_FAST = 32, 36, 37, 38  # JbvLink
STATE = dict(code=0, locals=4, refs=8, pc=12, sp=16, remaining=20, handles=24, pool=28, vm=32, frame=36, status=40, table=44, result=48, int_result=56, nursery=60, nursery_size=64, nursery_ref=68, nursery_size_ref=72, object_class=76, last_remembered=80)
LINK_OWNER, LINK_MEMBER, LINK_SEEN, LINK_TARGET_OWNER, LINK_TARGET, LINK_READY, LINK_ARGC, LINK_RESULT = 0, 8, 12, 16, 20, 39, 40, 42
FRAME_PC, FRAME_SP, FRAME_LOCALS = 12, 16, 24
ACT_SIZE, ACT_CALLER, ACT_ARGBASE, ACT_RESUME, ACT_KIND, ACT_ASM, ACT_RET = 168, 144, 152, 156, 157, 158, 160   # JbvActivation
ACT_C, ACT_M, ACT_LOCALS, ACT_STACK, ACT_LREFS, ACT_SREFS, ACT_SAVED, ACT_FRAME = 120, 124, 128, 132, 136, 140, 148, 88
F_PREV, F_OWNER, F_METHOD, F_PC, F_SP, F_BASE, F_LOCALS, F_MON = 0, 4, 8, 12, 16, 20, 24, 28   # JbvFrame
VM_MAX_SLOTS, VM_MAX_DEPTH, VM_SLOTS, VM_USED, VM_DEPTH, VM_REMAINING, VM_REFS, VM_FRAMES = 12, 16, 336, 340, 344, 352, 364, 368
CORE_LIMIT = 0x4C494D00   # enter_run: over a limit, nothing linked
VM_NURSERY, VM_NURSERY_TOP, VM_NURSERY_SIZE, VM_HEAP_BYTES, VM_HEAP_LIMIT, VM_CURSOR, VM_GENERATIONS, VM_OBJECT_COUNT, VM_HANDLES = 1984, 1988, 1992, 2036, 2040, 396, 380, 400, 376
VM_CAPACITY, VM_USED_BITS, VM_YOUNG = 392, 2108, 2112
LINK_SPECIAL_OWNER, LINK_SPECIAL, LINK_TRIVIAL, LINK_ADDRESS, LINK_PIC_SEEN, LINK_PIC_OWNER, LINK_PIC_TARGET = 24, 28, 43, 44, 48, 60, 72

handlers = {}   # opcode -> label
wide_handlers = {}   # opcode -> label, in op_table_w: entered with the two-slot top value also in xmm7
body = []
def handler(ops, label, code):
    for op in ops: handlers[op] = label
    body.append('ALIGN 16\n' + f'{label}:\n' + '\n'.join('    ' + line if line and not line.endswith(':') else line for line in code.strip('\n').splitlines()) + '\n')

def handler_w(ops, label, code):
    for op in ops: wide_handlers[op] = label
    body.append('ALIGN 16\n' + f'{label}:\n' + '\n'.join('    ' + line if line and not line.endswith(':') else line for line in code.strip('\n').splitlines()) + '\n')
WDISPATCH = ['movdqa xmm7, xmm0', 'DISPATCH_W']   # producers of a two-slot value (in xmm0's low quadword)
PUSH_INT = ['mov [edi+ebx*4], eax', 'mov BYTE PTR [ebp+ebx], 0', 'inc ebx']
PUSH_REF = ['mov [edi+ebx*4], eax', 'mov BYTE PTR [ebp+ebx], 1', 'inc ebx']
POP1 = ['dec ebx', 'mov eax, [edi+ebx*4-4]']
DISPATCH = ['DISPATCH']
def lines(*parts): return '\n'.join(line for part in parts for line in part)

for op, value in [(2, -1), (3, 0), (4, 1), (5, 2), (6, 3), (7, 4), (8, 5)]:
    handler([op], f'op_iconst_{op}', lines([f'mov eax, {value}'], PUSH_INT, DISPATCH))
handler([1], 'op_aconst_null', lines(['xor eax, eax'], PUSH_REF, DISPATCH))
handler([16], 'op_bipush', lines(['movsx eax, BYTE PTR [esi]', 'inc esi'], PUSH_INT, DISPATCH))
handler([17], 'op_sipush', lines(['movzx eax, WORD PTR [esi]', 'xchg al, ah', 'cwde', 'add esi, 2'], PUSH_INT, DISPATCH))
for op, size, read in [(18, 1, 'movzx ecx, BYTE PTR [esi]'), (19, 2, 'movzx ecx, WORD PTR [esi]\nxchg cl, ch')]:
    handler([op], f'op_ldc_{op}', lines(read.splitlines(), [
        f'imul ecx, ecx, {CONSTANT_SIZE}', 'mov edx, [esp]', f'add ecx, [edx+{STATE["pool"]}]',
        'mov dl, [ecx]', 'cmp dl, 3', 'je @F', 'cmp dl, 4', 'jne exit_op', '@@:',
        f'mov eax, [ecx+{CONSTANT_BITS}]', f'add esi, {size}'], PUSH_INT, DISPATCH))
for ops, ref in [((21,), 0), ((25,), 1)]:
    handler(ops, f'op_load_{ops[0]}', lines(['movzx ecx, BYTE PTR [esi]', 'inc esi', 'mov eax, [edi+ecx*4]'], PUSH_REF if ref else PUSH_INT, DISPATCH))
for base, ref in [(26, 0), (42, 1)]:
    for n in range(4):
        handler([base + n], f'op_load_{base + n}', lines([f'mov eax, [edi+{4 * n}]'], PUSH_REF if ref else PUSH_INT, DISPATCH))
for ops, ref in [((54,), 0), ((58,), 1)]:
    handler(ops, f'op_store_{ops[0]}', lines(['movzx ecx, BYTE PTR [esi]', 'inc esi', 'mov [edi+ecx*4], eax', f'mov BYTE PTR [ebp+ecx], {ref}'], POP1, DISPATCH))
for base, ref in [(59, 0), (75, 1)]:
    for n in range(4):
        handler([base + n], f'op_store_{base + n}', lines([f'mov [edi+{4 * n}], eax', f'mov BYTE PTR [ebp+{n}], {ref}'], POP1, DISPATCH))
handler([87], 'op_pop', lines(POP1, DISPATCH))
handler([88], 'op_pop2', lines(['sub ebx, 2', 'mov eax, [edi+ebx*4-4]'], DISPATCH))
handler([89], 'op_dup', lines(['mov [edi+ebx*4], eax', 'mov cl, [ebp+ebx-1]', 'mov [ebp+ebx], cl', 'inc ebx'], DISPATCH))
# dup_x1/dup_x2/dup2/dup2_x1/dup2_x2/swap: slot moves with their reference bits (copies = 1 or 2 slots, under `shift` more)
def dup_moves(copies, shift):
    code = []
    # new top region: stack[sp .. sp+copies) = the top `copies` slots
    for k in range(copies):
        code += [f'mov eax, [edi+ebx*4-{4 * (copies - k)}]', f'mov [edi+ebx*4+{4 * k}], eax',
                 f'mov cl, [ebp+ebx-{copies - k}]', f'mov [ebp+ebx+{k}], cl']
    # slide the `shift` slots below them up by `copies`
    for k in range(shift):
        src = copies + k + 1
        code += [f'mov eax, [edi+ebx*4-{4 * src}]', f'mov [edi+ebx*4-{4 * (src - copies)}], eax',
                 f'mov cl, [ebp+ebx-{src}]', f'mov [ebp+ebx-{src - copies}], cl']
    # the copied values go below the shifted ones
    for j in range(copies if shift else 0):   # slot j of the block: from sp+j to sp-copies-shift+j
        dst = copies + shift - j
        code += [f'mov eax, [edi+ebx*4+{4 * j}]', f'mov [edi+ebx*4-{4 * dst}], eax',
                 f'mov cl, [ebp+ebx+{j}]', f'mov [ebp+ebx-{dst}], cl']
    return code + [f'add ebx, {copies}', 'mov eax, [edi+ebx*4-4]']
for op, copies, shift in [(90, 1, 1), (91, 1, 2), (92, 2, 0), (93, 2, 1), (94, 2, 2)]:
    handler([op], f'op_dupx_{op}', lines(dup_moves(copies, shift), DISPATCH))
handler([95], 'op_swap', lines(['mov ecx, [edi+ebx*4-8]', 'mov [edi+ebx*4-4], ecx', 'mov [edi+ebx*4-8], eax', 'mov eax, ecx',
    'mov cl, [ebp+ebx-1]', 'mov dl, [ebp+ebx-2]', 'mov [ebp+ebx-1], dl', 'mov [ebp+ebx-2], cl'], DISPATCH))
# int binary operators: left operand in memory at sp-2, right in eax; the result slot keeps its int reference bit
for op, code in [(96, ['add eax, [edi+ebx*4-8]']), (104, ['imul eax, [edi+ebx*4-8]']),
                 (126, ['and eax, [edi+ebx*4-8]']), (128, ['or eax, [edi+ebx*4-8]']), (130, ['xor eax, [edi+ebx*4-8]']),
                 (100, ['mov ecx, eax', 'mov eax, [edi+ebx*4-8]', 'sub eax, ecx']),
                 (120, ['mov ecx, eax', 'mov eax, [edi+ebx*4-8]', 'shl eax, cl']),
                 (122, ['mov ecx, eax', 'mov eax, [edi+ebx*4-8]', 'sar eax, cl']),
                 (124, ['mov ecx, eax', 'mov eax, [edi+ebx*4-8]', 'shr eax, cl'])]:
    handler([op], f'op_int_{op}', lines(code, ['dec ebx', 'mov [edi+ebx*4-4], eax'], DISPATCH))
for op, check in [(108, 'quotient'), (112, 'remainder')]:
    handler([op], f'op_int_{op}', lines([
        'mov ecx, eax', 'test ecx, ecx', 'jz exit_op', 'cmp ecx, -1', 'je exit_op',   # zero or MIN/-1: C
        'mov eax, [edi+ebx*4-8]', 'cdq', 'idiv ecx'] + (['mov eax, edx'] if op == 112 else []),
        ['dec ebx', 'mov [edi+ebx*4-4], eax'], DISPATCH))
handler([116], 'op_ineg', lines(['neg eax', 'mov [edi+ebx*4-4], eax'], DISPATCH))
handler([132], 'op_iinc', lines(['movzx ecx, BYTE PTR [esi]', 'movsx edx, BYTE PTR [esi+1]', 'add esi, 2', 'add [edi+ecx*4], edx'], DISPATCH))
for op, code in [(145, 'movsx eax, al'), (146, 'movzx eax, ax'), (147, 'movsx eax, ax')]:
    handler([op], f'op_narrow_{op}', lines([code, 'mov [edi+ebx*4-4], eax'], DISPATCH))

# Branches. The budget is charged before any operand is popped, so on exhaustion C
# can re-execute the branch from the unchanged stack and report the limit.
OFFSET = ['movzx edx, WORD PTR [esi]', 'xchg dl, dh', 'movsx edx, dx']
cold = []   # rarely taken tails, emitted after the handlers
def budget(label):   # edx = offset; backward branches cost one unit; exhausted: back to C
    cold.append('\n'.join([f'{label}_borrow:                ; the low word was 0: borrow from the high word, or stop',
        f'    cmp DWORD PTR [ecx+4], 0', f'    je {label}_out', '    dec DWORD PTR [ecx+4]', f'    jmp {label}_back',
        f'{label}_out:', '    mov DWORD PTR [ecx], 0', '    jmp exit_op', '']))
    return ['test edx, edx', f'jg {label}', 'mov ecx, [esp]', f'mov ecx, [ecx+{STATE["remaining"]}]',
            'sub DWORD PTR [ecx], 1', f'jc {label}_borrow', f'{label}_back:', f'{label}:']
counter = [0]
def branch(ops, name, test, jump_if_not, pops):
    counter[0] += 1
    n = counter[0]
    pop = POP1 if pops == 1 else ['sub ebx, 2', 'mov eax, [edi+ebx*4-4]']
    handler(ops, name, lines(test, [f'{jump_if_not} br_no_{n}'], OFFSET, budget(f'br_go_{n}'), pop,
                             ['lea esi, [esi+edx-1]'], DISPATCH, [f'br_no_{n}:'], pop, ['add esi, 2'], DISPATCH))
for op, inverse in [(153, 'jne'), (154, 'je'), (155, 'jge'), (156, 'jl'), (157, 'jle'), (158, 'jg')]:
    branch([op], f'op_if_{op}', ['test eax, eax'], inverse, 1)
for op, inverse in [(159, 'jne'), (160, 'je'), (161, 'jge'), (162, 'jl'), (163, 'jle'), (164, 'jg'), (165, 'jne'), (166, 'je')]:
    branch([op], f'op_ifcmp_{op}', ['cmp [edi+ebx*4-8], eax'], inverse, 2)
branch([198], 'op_ifnull', ['test eax, eax'], 'jne', 1)
branch([199], 'op_ifnonnull', ['test eax, eax'], 'je', 1)
handler([167], 'op_goto', lines(OFFSET, budget('goto_go'), ['lea esi, [esi+edx-1]'], DISPATCH))
def switch_table():   # ecx = the 4-aligned operands after the opcode at esi-1
    return ['mov edx, [esp]', 'mov ecx, esi', f'sub ecx, [edx+{STATE["code"]}]', 'add ecx, 3', 'and ecx, -4', f'add ecx, [edx+{STATE["code"]}]']
handler([170], 'op_tableswitch', lines(switch_table(), [
    'push ebp', 'mov ebp, [ecx+4]', 'bswap ebp', 'mov edx, [ecx+8]', 'bswap edx', 'sub eax, ebp', 'sub edx, ebp', 'pop ebp',
    'cmp eax, edx', 'ja ts_default', 'mov edx, [ecx+eax*4+12]', 'bswap edx', 'jmp ts_go0',
    'ts_default:', 'mov edx, [ecx]', 'bswap edx', 'ts_go0:'], budget('ts_go'), POP1, ['lea esi, [esi+edx-1]'], DISPATCH))
handler([171], 'op_lookupswitch', lines(switch_table(), [
    'push esi', 'push ebp', 'push ebx', 'xor ebp, ebp', 'mov edx, [ecx+4]', 'bswap edx',      # lo = 0, hi = npairs
    'ls_loop:', 'cmp ebp, edx', 'jge ls_default', 'lea ebx, [ebp+edx]', 'shr ebx, 1',
    'mov esi, [ecx+ebx*8+8]', 'bswap esi', 'cmp eax, esi', 'je ls_found', 'jl ls_less', 'lea ebp, [ebx+1]', 'jmp ls_loop',
    'ls_less:', 'mov edx, ebx', 'jmp ls_loop',
    'ls_found:', 'mov edx, [ecx+ebx*8+12]', 'bswap edx', 'jmp ls_go0',
    'ls_default:', 'mov edx, [ecx]', 'bswap edx',
    'ls_go0:', 'pop ebx', 'pop ebp', 'pop esi'], budget('ls_go'), POP1, ['lea esi, [esi+edx-1]'], DISPATCH))

# Objects: references are handle indexes; the handle table holds object pointers
# (header word, then fields/elements; an array's length is the word before it).
def deref(reg):   # reg = non-null reference -> object pointer
    return [f'and {reg}, 0FFFFFFh', 'mov edx, [esp]', f'mov edx, [edx+{STATE["handles"]}]', f'mov {reg}, [edx+{reg}*4]']
handler([190], 'op_arraylength', lines(['test eax, eax', 'jz exit_op', 'mov ecx, eax'], deref('ecx'),
                                       ['mov eax, [ecx-4]', 'mov [edi+ebx*4-4], eax', 'mov BYTE PTR [ebp+ebx-1], 0'], DISPATCH))
for op, load, ref in [(46, 'mov eax, [ecx+eax*4+4]', 0), (50, 'mov eax, [ecx+eax*4+4]', 1), (51, 'movsx eax, BYTE PTR [ecx+eax+4]', 0),
                      (52, 'movzx eax, WORD PTR [ecx+eax*2+4]', 0), (53, 'movsx eax, WORD PTR [ecx+eax*2+4]', 0)]:
    handler([op], f'op_xaload_{op}', lines(['mov ecx, [edi+ebx*4-8]', 'test ecx, ecx', 'jz exit_op'], deref('ecx'),
        ['cmp eax, [ecx-4]', 'jae exit_op', load, 'dec ebx', 'mov [edi+ebx*4-4], eax', f'mov BYTE PTR [ebp+ebx-1], {ref}'], DISPATCH))
for op, store in [(79, 'mov [ecx+edx*4+4], eax'), (85, 'mov [ecx+edx*2+4], ax'), (86, 'mov [ecx+edx*2+4], ax')]:
    handler([op], f'op_xastore_{op}', lines(['mov ecx, [edi+ebx*4-12]', 'test ecx, ecx', 'jz exit_op'], deref('ecx'),
        ['mov edx, [edi+ebx*4-8]', 'cmp edx, [ecx-4]', 'jae exit_op', store, 'sub ebx, 3', 'mov eax, [edi+ebx*4-4]'], DISPATCH))
# Write barrier (as jbv_barrier): storing a young reference into an old object
# remembers the object (jbv_remember, which neither allocates on the Java heap nor collects).
# owner = object pointer register; the value is the top of stack. Uses eax and [esp] scratch.
def barrier(owner, n):
    S = STATE
    return ['mov eax, [edi+ebx*4-4]', 'test eax, eax', f'jz wb_ok_{n}', 'push edx', 'mov eax, ' + owner, 'mov edx, [esp+4]',
            f'sub eax, [edx+{S["nursery"]}]', f'cmp eax, [edx+{S["nursery_size"]}]', f'jb wb_young_{n}',
            'mov eax, [edi+ebx*4-4]', 'and eax, 0FFFFFFh', f'mov edx, [edx+{S["handles"]}]', 'mov eax, [edx+eax*4]',
            'mov edx, [esp+4]', f'sub eax, [edx+{S["nursery"]}]', f'cmp eax, [edx+{S["nursery_size"]}]', f'jb wb_c_{n}',
            f'wb_young_{n}:', 'pop edx', f'jmp wb_ok_{n}',
            f'wb_c_{n}:', f'mov eax, [edx+{S["last_remembered"]}]', 'mov eax, [eax]', 'pop edx', f'cmp eax, {owner}', f'je wb_ok_{n}',   # already remembered
            'push ecx', 'push edx'] + ([] if owner == 'edx' else [f'mov edx, {owner}']) + [
            'mov ecx, [esp+8]', f'mov ecx, [ecx+{S["vm"]}]', 'call @jbv_remember@8', 'pop edx', 'pop ecx', f'wb_ok_{n}:']   # jbv_remember(vm, owner)

# getfield/putfield of a resolved one-slot instance field (JbvLink.fast == 1)
LINK = ['movzx ecx, WORD PTR [esi]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'mov edx, [esp]',
        f'add ecx, [edx+{STATE["pool"]}]', f'mov ecx, [ecx+{CONSTANT_LINK}]', 'test ecx, ecx', 'jz exit_op',
        f'cmp BYTE PTR [ecx+{LINK_FAST}], 1', 'jne exit_op']
handler([180], 'op_getfield', lines(LINK, ['test eax, eax', 'jz exit_op'], deref('eax'), [   # deref keeps ecx
    f'mov edx, [ecx+{LINK_SLOT}]', 'mov eax, [eax+edx*4+4]', f'mov cl, [ecx+{LINK_KIND}]',
    'mov [edi+ebx*4-4], eax', 'mov [ebp+ebx-1], cl', 'add esi, 2'], DISPATCH))
handler([181], 'op_putfield', lines(LINK, [
    f'mov dx, WORD PTR [ecx+{LINK_KIND}]', 'cmp dx, 4900h', 'je put_go', 'cmp dl, 1', 'jne exit_op',   # int 'I' or a reference
    'put_go:',
    'mov dl, [ecx+%d]' % LINK_KIND, 'push edx', f'mov ecx, [ecx+{LINK_SLOT}]', 'mov edx, [edi+ebx*4-8]', 'test edx, edx', 'jz put_null',
    'and edx, 0FFFFFFh', 'mov eax, [esp+4]', f'mov eax, [eax+{STATE["handles"]}]', 'mov edx, [eax+edx*4]',
    'pop eax', 'cmp al, 1', 'jne put_store'] + barrier('edx', 'put') + [
    'put_store:', 'mov eax, [edi+ebx*4-4]', 'mov [edx+ecx*4+4], eax', 'sub ebx, 2', 'mov eax, [edi+ebx*4-4]', 'add esi, 2'], DISPATCH,
    ['put_null:', 'pop edx', 'jmp exit_op']))
# getstatic/putstatic of a one-slot int/reference field of an initialized class (no barrier: statics are roots)
STATIC = LINK[:-2] + [f'cmp BYTE PTR [ecx+{LINK_FAST}], 2', 'jne exit_op', f'cmp BYTE PTR [ecx+{LINK_READY}], 1', 'jne exit_op']
handler([178], 'op_getstatic', lines(STATIC, [f'mov edx, [ecx+{LINK_ADDRESS}]', 'mov eax, [edx]', f'mov dl, [ecx+{LINK_KIND}]',
    'mov [edi+ebx*4], eax', 'mov [ebp+ebx], dl', 'inc ebx', 'add esi, 2'], DISPATCH))
handler([179], 'op_putstatic', lines(STATIC, [f'mov dx, WORD PTR [ecx+{LINK_KIND}]', 'cmp dx, 4900h', 'je @F', 'cmp dl, 1', 'jne exit_op', '@@:',
    f'mov edx, [ecx+{LINK_ADDRESS}]', 'mov [edx], eax'], POP1, ['add esi, 2'], DISPATCH))
# aastore: null, or an exact component class, or an Object[]; then the barrier
handler([83], 'op_aastore', lines(['mov ecx, [edi+ebx*4-12]', 'test ecx, ecx', 'jz exit_op'], deref('ecx'), [
    'mov edx, [edi+ebx*4-8]', 'cmp edx, [ecx-4]', 'jae exit_op', 'test eax, eax', 'jz aa_store',
    'push edx', 'mov edx, [esp+4]',                                                   # [esp] index; edx state
    'mov eax, [ecx]', 'mov eax, [eax+CLASS_COMPONENT]', f'cmp eax, [edx+{STATE["object_class"]}]', 'je aa_typed',   # Object[]: any value
    'push eax', 'mov eax, [edi+ebx*4-4]', 'and eax, 0FFFFFFh', f'mov edx, [edx+{STATE["handles"]}]', 'mov eax, [edx+eax*4]',
    'mov eax, [eax]', 'cmp eax, [esp]', 'pop eax', 'jne aa_c', 'mov edx, [esp+4]',      # exactly the component class
    'aa_typed:',                                                                       # write barrier: old array, young value
    'mov eax, ecx', f'sub eax, [edx+{STATE["nursery"]}]', f'cmp eax, [edx+{STATE["nursery_size"]}]', 'jb aa_ok',
    'mov eax, [edi+ebx*4-4]', 'and eax, 0FFFFFFh', 'push ecx', f'mov ecx, [edx+{STATE["handles"]}]', 'mov eax, [ecx+eax*4]', 'pop ecx',
    f'sub eax, [edx+{STATE["nursery"]}]', f'cmp eax, [edx+{STATE["nursery_size"]}]', 'jae aa_ok',
    f'mov eax, [edx+{STATE["last_remembered"]}]', 'cmp ecx, [eax]', 'je aa_ok',
    'push ecx', 'mov eax, edx', 'mov edx, ecx', f'mov ecx, [eax+{STATE["vm"]}]', 'call @jbv_remember@8', 'pop ecx',
    'aa_ok:', 'pop edx',
    'aa_store:', 'mov eax, [edi+ebx*4-4]', 'mov [ecx+edx*4+4], eax', 'sub ebx, 3', 'mov eax, [edi+ebx*4-4]'], DISPATCH,
    ['aa_c:', 'pop edx', 'jmp exit_op']))

# Calls: invokestatic of a ready link, invokevirtual/invokeinterface hitting the
# monomorphic cache. The core syncs the frame and calls jbv_execute itself (fastcall:
# ecx vm, edx class; m, args, refs, count, result on the stack, popped by the callee).
METHOD_LINK = ['movzx ecx, WORD PTR [esi]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'mov edx, [esp]',
               f'add ecx, [edx+{STATE["pool"]}]', f'mov ecx, [ecx+{CONSTANT_LINK}]', 'test ecx, ecx', 'jz exit_op']
def call(size, n):
    """One call sequence per invoke opcode: ecx = link, edx = method, eax = owner."""
    S = STATE
    sync = ['mov eax, esi', 'dec eax', f'sub eax, [edx+{S["code"]}]', f'mov [edx+{S["pc"]}], eax',      # edx = state
            f'mov edx, [edx+{S["frame"]}]', f'mov [edx+{FRAME_PC}], eax',
            'mov eax, ebx', f'sub eax, [edx+{FRAME_LOCALS}]', f'mov [edx+{FRAME_SP}], eax']
    return [
        # plain bytecode callee: an activation on this stack, then dispatch in it
        'test WORD PTR [edx], 0520h', f'jnz call_c_{n}',   # native, synchronized, abstract: C
        'cmp BYTE PTR [edx+METHOD_ACCESSOR], 0', f'jne acc_{n}', f'acc_back_{n}:',
        'push eax', 'push edx', 'mov edx, [esp+8]'] + sync + ['pop edx', 'pop eax',
        f'movzx ecx, WORD PTR [ecx+{LINK_ARGC}]', 'neg ecx', 'add ecx, ebx',                  # argbase
        f'sub esp, {ACT_SIZE}', 'push esp',                                                   # [esp] = callee activation
        'call enter_run',                                                                     # eax = status; [esp] = callee
        f'cmp eax, {CORE_LIMIT}', f'je call_limit_{n}',
        'pop ecx', f'mov edx, [ecx+{ACT_CALLER}]',
        f'movq xmm0, QWORD PTR [ecx+{S["result"]}]', f'movq QWORD PTR [edx+{S["result"]}], xmm0',
        f'mov ebx, [ecx+{ACT_ARGBASE}]', f'movzx ebp, BYTE PTR [ecx+{ACT_KIND}]', f'add esp, {ACT_SIZE}',
        f'mov edi, [edx+{S["locals"]}]', f'mov esi, [edx+{S["code"]}]', f'add esi, [edx+{S["pc"]}]', 'inc esi',
        'test eax, eax', 'jnz frame_failed', f'add esi, {size}', 'mov ecx, ebp', f'mov ebp, [edx+{S["refs"]}]',
        f'jmp call_result_{n}',
        f'call_limit_{n}:', 'pop eax', f'add esp, {ACT_SIZE}', 'jmp exit_op',               # limits: C reports them (esi, ebx kept)
        # accessors, inline once the field is resolved: getter (receiver -> value), int setter
        f'acc_{n}:', 'push ecx', 'push eax', 'mov ecx, [edx+METHOD_CODE]',
        'cmp BYTE PTR [edx+METHOD_ACCESSOR], 1', f'jne acc_set_{n}',
        'movzx ecx, WORD PTR [ecx+2]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'add ecx, [eax+8]', f'mov ecx, [ecx+{CONSTANT_LINK}]',
        'test ecx, ecx', f'jz acc_fail_{n}', f'cmp BYTE PTR [ecx+{LINK_FAST}], 1', f'jne acc_fail_{n}',
        'mov eax, [edi+ebx*4-4]', 'and eax, 0FFFFFFh', 'mov edx, [esp+8]', f'mov edx, [edx+{S["handles"]}]', 'mov eax, [edx+eax*4]',
        f'mov edx, [ecx+{LINK_SLOT}]', 'mov eax, [eax+edx*4+4]', f'mov dl, [ecx+{LINK_KIND}]',
        'mov [edi+ebx*4-4], eax', 'mov [ebp+ebx-1], dl', 'add esp, 8', f'add esi, {size}', 'DISPATCH',
        f'acc_set_{n}:', 'movzx ecx, WORD PTR [ecx+3]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'add ecx, [eax+8]', f'mov ecx, [ecx+{CONSTANT_LINK}]',
        'test ecx, ecx', f'jz acc_fail_{n}', f'cmp BYTE PTR [ecx+{LINK_FAST}], 1', f'jne acc_fail_{n}', f'cmp WORD PTR [ecx+{LINK_KIND}], 4900h', f'jne acc_fail_{n}',
        'mov eax, [edi+ebx*4-8]', 'and eax, 0FFFFFFh', 'mov edx, [esp+8]', f'mov edx, [edx+{S["handles"]}]', 'mov eax, [edx+eax*4]',
        f'mov edx, [ecx+{LINK_SLOT}]', 'mov ecx, [edi+ebx*4-4]', 'mov [eax+edx*4+4], ecx',
        'sub ebx, 2', 'mov eax, [edi+ebx*4-4]', 'add esp, 8', f'add esi, {size}', 'DISPATCH',
        f'acc_fail_{n}:', 'pop eax', 'pop ecx', f'jmp acc_back_{n}',
        f'call_c_{n}:',                                                                       # through jbv_execute
        'push eax', 'push edx', 'mov edx, [esp+8]'] + sync + [
        f'movzx eax, WORD PTR [ecx+{LINK_ARGC}]', 'neg eax', 'add eax, ebx',              # argbase
        'pop edx', 'push ecx', 'push eax',                                                # [esp] argbase, link, owner, state
        'mov ecx, [esp+12]', f'lea ecx, [ecx+{S["result"]}]', 'push ecx',                # result
        'mov ecx, [esp+8]', f'movzx ecx, WORD PTR [ecx+{LINK_ARGC}]', 'push ecx',         # count
        'lea ecx, [ebp+eax]', 'push ecx', 'lea ecx, [edi+eax*4]', 'push ecx', 'push edx', # refs, args, m
        'mov edx, [esp+28]', 'mov ecx, [esp+32]', f'mov ecx, [ecx+{S["vm"]}]',
        'call @jbv_execute@28',
        'pop ebx', 'pop ecx', 'add esp, 4', 'mov edx, [esp]',                             # sp = argbase; link; state
        'test eax, eax', 'jnz call_failed', f'movzx ecx, BYTE PTR [ecx+{LINK_RESULT}]', f'add esi, {size}',
        # the result: ecx = result kind, edx = the caller (the call may have collected)
        f'call_result_{n}:',
        f'mov eax, [edx+{S["table"]}]', 'mov eax, [eax]', f'mov [edx+{S["handles"]}], eax',
        f'mov eax, [edx+{S["nursery_ref"]}]', 'mov eax, [eax]', f'mov [edx+{S["nursery"]}], eax',
        f'mov eax, [edx+{S["nursery_size_ref"]}]', 'mov eax, [eax]', f'mov [edx+{S["nursery_size"]}], eax',
        'test ecx, ecx', f'jz fd_void_{n}', 'cmp cl, 3', f'je fd_wide_{n}', 'cmp cl, 6', f'je fd_wide_{n}',
        'cmp cl, 2', 'sete al', 'mov [ebp+ebx], al',
        f'mov eax, [edx+{S["result"]}]', 'mov [edi+ebx*4], eax', 'inc ebx', 'DISPATCH',
        f'fd_wide_{n}:', f'movq xmm0, QWORD PTR [edx+{S["result"]}]', 'movq QWORD PTR [edi+ebx*4], xmm0',
        'mov BYTE PTR [ebp+ebx], 0', 'mov BYTE PTR [ebp+ebx+1], 0', 'add ebx, 2', 'mov eax, [edi+ebx*4-4]', 'DISPATCH',
        f'fd_void_{n}:', 'mov eax, [edi+ebx*4-4]', 'DISPATCH']
body.append('call_failed:                     ; eax = status, edx = state; esi just past the opcode\n'
            f'    mov [edx+{STATE["status"]}], eax\n    jmp exit_op\n')
handler([184], 'op_invokestatic', lines(METHOD_LINK, [f'cmp BYTE PTR [ecx+{LINK_READY}], 1', 'jne exit_op'],
                                        [f'mov edx, [ecx+{LINK_MEMBER}]', f'mov eax, [ecx+{LINK_OWNER}]'], call(2, 'st')))
for op, size in [(182, 2), (185, 4)]:
    entries = [(LINK_SEEN, LINK_TARGET_OWNER, LINK_TARGET)] + [(LINK_PIC_SEEN + 4 * k, LINK_PIC_OWNER + 4 * k, LINK_PIC_TARGET + 4 * k) for k in range(3)]
    code = METHOD_LINK + [f'mov edx, [ecx+{LINK_SPECIAL}]', 'test edx, edx', f'jz inv_{op}_pic',   # private/final: one target
            f'movzx eax, WORD PTR [ecx+{LINK_ARGC}]', 'neg eax', 'add eax, ebx', 'cmp DWORD PTR [edi+eax*4], 0', 'je exit_op',
            f'mov eax, [ecx+{LINK_SPECIAL_OWNER}]', f'jmp inv_{op}_call', f'inv_{op}_pic:',
            f'mov edx, [ecx+{LINK_SEEN}]', 'test edx, edx', 'jz exit_op',
            f'movzx eax, WORD PTR [ecx+{LINK_ARGC}]', 'neg eax', 'add eax, ebx', 'mov eax, [edi+eax*4]',  # receiver = locals[sp - argc]
            'test eax, eax', 'jz exit_op', 'and eax, 0FFFFFFh', 'mov edx, [esp]', f'mov edx, [edx+{STATE["handles"]}]',
            'mov eax, [edx+eax*4]', 'mov eax, [eax]']
    code += [f'cmp eax, [ecx+{seen}]\nje inv_{op}_{k}' for k, (seen, _, _) in enumerate(entries)] + ['jmp exit_op']
    for k, (_, owner, target) in enumerate(entries):
        code += [f'inv_{op}_{k}:', f'mov edx, [ecx+{target}]', f'mov eax, [ecx+{owner}]', f'jmp inv_{op}_call']
    code += [f'inv_{op}_call:'] + call(size, op)
    handler([op], f'op_invoke_{op}', '\n'.join(code))
handler([183], 'op_invokespecial', lines(METHOD_LINK, [
    f'mov edx, [ecx+{LINK_SPECIAL}]', 'test edx, edx', 'jz exit_op',
    f'movzx eax, WORD PTR [ecx+{LINK_ARGC}]', 'neg eax', 'add eax, ebx', 'cmp DWORD PTR [edi+eax*4], 0', 'je exit_op',   # null receiver: C
    f'cmp BYTE PTR [ecx+{LINK_TRIVIAL}], 1', 'jne special_call',
    'mov ebx, eax', 'mov eax, [edi+ebx*4-4]', 'add esi, 2'], DISPATCH, ['special_call:', f'mov edx, [ecx+{LINK_SPECIAL}]', f'mov eax, [ecx+{LINK_SPECIAL_OWNER}]'], call(2, 'sp')))

# new of a resolved, initialized, concrete class: jbv_new(vm, type, 0, &ref), which may collect
def sync_frame():
    S = STATE
    return ['mov edx, [esp]', 'mov eax, esi', 'dec eax', f'sub eax, [edx+{S["code"]}]', f'mov edx, [edx+{S["frame"]}]',
            f'mov [edx+{FRAME_PC}], eax', 'mov eax, ebx', f'sub eax, [edx+{FRAME_LOCALS}]', f'mov [edx+{FRAME_SP}], eax']
def reload_after_call():   # edx = state
    S = STATE
    return [f'mov eax, [edx+{S["table"]}]', 'mov eax, [eax]', f'mov [edx+{S["handles"]}], eax',
            f'mov eax, [edx+{S["nursery_ref"]}]', 'mov eax, [eax]', f'mov [edx+{S["nursery"]}], eax',
            f'mov eax, [edx+{S["nursery_size_ref"]}]', 'mov eax, [eax]', f'mov [edx+{S["nursery_size"]}], eax']
handler([187], 'op_new', lines(['movzx ecx, WORD PTR [esi]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'mov edx, [esp]',
    f'add ecx, [edx+{STATE["pool"]}]', 'cmp BYTE PTR [ecx], 7', 'jne exit_op', f'mov ecx, [ecx+{CONSTANT_LINK}]', 'test ecx, ecx', 'jz exit_op',
    'cmp BYTE PTR [ecx+CLASS_INIT], 2', 'jne exit_op', 'test WORD PTR [ecx+CLASS_FLAGS], 0600h', 'jnz exit_op',
    'IF JBV_GC_STRESS EQ 0',   # a plain object in the pre-zeroed young region, a free handle at the cursor
    'mov edx, [esp]', f'mov edx, [edx+{STATE["vm"]}]',
    f'mov eax, [edx+{VM_OBJECT_COUNT}]', f'cmp eax, [edx+{VM_CAPACITY}]', 'jae new_c',   # a handle is free (and the bitmaps exist)
    'mov eax, [ecx+CLASS_SLOTS]', 'lea eax, [eax*4+8]', 'cmp eax, 516', 'ja new_c',
    'push esi', 'push ebx', 'push ecx', 'push eax',                                   # bytes, class, ebx, esi
    f'mov esi, [edx+{VM_NURSERY}]', f'add esi, [edx+{VM_NURSERY_SIZE}]', f'sub esi, [edx+{VM_NURSERY_TOP}]',
    'cmp esi, eax', 'jb new_c_pop', f'mov esi, [edx+{VM_HEAP_LIMIT}]', f'sub esi, [edx+{VM_HEAP_BYTES}]', 'jb new_c_pop', 'cmp esi, eax', 'jb new_c_pop',
    f'mov esi, [edx+{VM_USED_BITS}]', f'mov ebx, [edx+{VM_CURSOR}]', 'mov eax, [esi+ebx*4]', 'not eax', 'bsf ecx, eax', 'jz new_c_pop',   # else C searches on
    'mov eax, 1', 'shl eax, cl', 'or [esi+ebx*4], eax', f'mov esi, [edx+{VM_YOUNG}]', 'or [esi+ebx*4], eax',
    'shl ebx, 5', 'or ebx, ecx', f'inc DWORD PTR [edx+{VM_OBJECT_COUNT}]',                # ebx = handle index
    f'mov ecx, [edx+{VM_GENERATIONS}]', 'movzx eax, BYTE PTR [ecx+ebx]', 'inc eax', 'cmp eax, 128', 'jb @F', 'mov eax, 1', '@@:',
    'mov [ecx+ebx], al', 'shl eax, 24', 'or eax, ebx',                                    # eax = the reference
    'pop ecx', f'add [edx+{VM_HEAP_BYTES}], ecx', f'mov esi, [edx+{VM_NURSERY_TOP}]', f'add [edx+{VM_NURSERY_TOP}], ecx',
    'pop ecx', 'mov [esi+4], ecx', 'lea ecx, [esi+4]', f'mov esi, [edx+{VM_HANDLES}]', 'mov [esi+ebx*4], ecx',
    'pop ebx', 'pop esi', 'mov [edi+ebx*4], eax', 'mov BYTE PTR [ebp+ebx], 1', 'inc ebx', 'add esi, 2', 'DISPATCH',
    'new_c_pop:', 'pop eax', 'pop ecx', 'pop ebx', 'pop esi', 'new_c:', 'ENDIF'],
    sync_frame(), ['mov edx, ecx', 'mov ecx, [esp]', f'lea eax, [ecx+{STATE["result"]}]', 'push eax', 'push 0',
    f'mov ecx, [ecx+{STATE["vm"]}]', 'call @jbv_new@16', 'mov edx, [esp]', 'test eax, eax', 'jnz call_failed'], reload_after_call(),
    [f'mov eax, [edx+{STATE["result"]}]', 'mov [edi+ebx*4], eax', 'mov BYTE PTR [ebp+ebx], 1', 'inc ebx', 'add esi, 2'], DISPATCH))

# Superinstructions: 203 = aload_0 getfield, 204 = iinc goto (the rest of the pair is
# unchanged; on any special case the core leaves the marker to C, which runs the first opcode).
handler([203], 'op_this_getfield', lines(['movzx ecx, WORD PTR [esi+1]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'mov edx, [esp]',
    f'add ecx, [edx+{STATE["pool"]}]', f'mov ecx, [ecx+{CONSTANT_LINK}]', 'test ecx, ecx', 'jz exit_op',
    f'cmp BYTE PTR [ecx+{LINK_FAST}], 1', 'jne exit_op', 'mov eax, [edi]', 'test eax, eax', 'jz exit_op'], deref('eax'), [
    f'mov edx, [ecx+{LINK_SLOT}]', 'mov eax, [eax+edx*4+4]', f'mov cl, [ecx+{LINK_KIND}]',
    'mov [edi+ebx*4], eax', 'mov [ebp+ebx], cl', 'inc ebx', 'add esi, 3'], DISPATCH))
handler([204], 'op_iinc_goto', lines(['movzx edx, WORD PTR [esi+3]', 'xchg dl, dh', 'movsx edx, dx'], budget('iinc_goto_go'), [
    'movzx ecx, BYTE PTR [esi]', 'lea ecx, [edi+ecx*4]', 'push edx', 'movsx edx, BYTE PTR [esi+1]', 'add [ecx], edx', 'pop edx',
    'lea esi, [esi+edx+2]'], DISPATCH))

# checkcast/instanceof against a resolved class: null and the exact class here, the rest in C
CLASS_REF = ['movzx ecx, WORD PTR [esi]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'mov edx, [esp]',
             f'add ecx, [edx+{STATE["pool"]}]', 'cmp BYTE PTR [ecx], 7', 'jne exit_op', f'mov ecx, [ecx+{CONSTANT_LINK}]', 'test ecx, ecx', 'jz exit_op']
def receiver_class():   # eax = non-null reference -> edx = its class (eax kept)
    return ['mov edx, eax', 'and edx, 0FFFFFFh', 'push ecx', 'mov ecx, [esp+4]', f'mov ecx, [ecx+{STATE["handles"]}]',
            'mov edx, [ecx+edx*4]', 'pop ecx', 'mov edx, [edx]']
handler([192], 'op_checkcast', lines(CLASS_REF, ['test eax, eax', 'jz cc_ok'], receiver_class(),
    ['cmp edx, ecx', 'jne exit_op', 'cc_ok:', 'add esi, 2'], DISPATCH))
handler([193], 'op_instanceof', lines(CLASS_REF, ['test eax, eax', 'jz io_store'], receiver_class(),
    ['cmp edx, ecx', 'jne exit_op', 'mov eax, 1', 'io_store:', 'mov [edi+ebx*4-4], eax', 'mov BYTE PTR [ebp+ebx-1], 0', 'add esi, 2'], DISPATCH))

# float/long/double. Two-slot values keep the low word in the lower slot; eax is the
# top slot (the high word). Doubles and floats use SSE2 (IEEE, the VM's MXCSR); cases
# with special Java results (division, remainder, out-of-range or NaN conversions) go to C.
TOP = 'mov eax, [edi+ebx*4-4]'
# Store forwarding: every two-slot value is written by one 8-byte store; 4-byte loads of
# its halves and 8-byte loads of the whole then forward. (Two 4-byte stores read back
# by one 8-byte load would stall.)
def store64(addr):   # edx:eax -> addr
    return ['movd xmm0, eax', 'movd xmm1, edx', 'punpckldq xmm0, xmm1', f'movq QWORD PTR {addr}, xmm0']
PUSH_ZERO_REF = ['mov BYTE PTR [ebp+ebx], 0']
for op, n in [(23, None), (34, 0), (35, 1), (36, 2), (37, 3)]:            # fload
    src = ['movzx ecx, BYTE PTR [esi]', 'inc esi', 'mov eax, [edi+ecx*4]'] if n is None else [f'mov eax, [edi+{4 * n}]']
    handler([op], f'op_fload_{op}', lines(src, PUSH_INT, DISPATCH))
for op, n in [(56, None), (67, 0), (68, 1), (69, 2), (70, 3)]:            # fstore
    dst = ['movzx ecx, BYTE PTR [esi]', 'inc esi', 'mov [edi+ecx*4], eax', 'mov BYTE PTR [ebp+ecx], 0'] if n is None else \
          [f'mov [edi+{4 * n}], eax', f'mov BYTE PTR [ebp+{n}], 0']
    handler([op], f'op_fstore_{op}', lines(dst, POP1, DISPATCH))
for ops, n in [((22, 24), None), ((30, 38), 0), ((31, 39), 1), ((32, 40), 2), ((33, 41), 3)]:   # lload/dload
    src = ['movzx ecx, BYTE PTR [esi]', 'inc esi', 'movq xmm0, QWORD PTR [edi+ecx*4]', 'mov eax, [edi+ecx*4+4]'] if n is None else \
          [f'movq xmm0, QWORD PTR [edi+{4 * n}]', f'mov eax, [edi+{4 * n + 4}]']
    handler(ops, f'op_wload_{ops[0]}', lines(src, ['movq QWORD PTR [edi+ebx*4], xmm0',
        'mov BYTE PTR [ebp+ebx], 0', 'mov BYTE PTR [ebp+ebx+1], 0', 'add ebx, 2'], WDISPATCH))
for ops, n in [((55, 57), None), ((63, 71), 0), ((64, 72), 1), ((65, 73), 2), ((66, 74), 3)]:   # lstore/dstore
    dst = ['movzx ecx, BYTE PTR [esi]', 'inc esi'] if n is None else []
    at = (lambda k: f'[edi+ecx*4+{k}]') if n is None else (lambda k: f'[edi+{4 * n + k}]')
    rb = (lambda k: f'BYTE PTR [ebp+ecx+{k}]') if n is None else (lambda k: f'BYTE PTR [ebp+{n + k}]')
    handler(ops, f'op_wstore_{ops[0]}', lines(dst, ['movq xmm0, QWORD PTR [edi+ebx*4-8]', f'movq QWORD PTR {at(0)}, xmm0',
        f'mov {rb(0)}, 0', f'mov {rb(1)}, 0', 'sub ebx, 2', TOP], DISPATCH))
    handler_w(ops, f'op_wstorew_{ops[0]}', lines(dst, [f'movq QWORD PTR {at(0)}, xmm7',
        f'mov {rb(0)}, 0', f'mov {rb(1)}, 0', 'sub ebx, 2', TOP], DISPATCH))
for op, lo, hi in [(9, 0, 0), (10, 1, 0), (14, 0, 0), (15, 0, 0x3ff00000)]:   # lconst, dconst
    handler([op], f'op_wconst_{op}', lines([f'mov eax, {lo}', f'mov edx, {hi}'], store64('[edi+ebx*4]'), ['mov eax, edx',
        'mov BYTE PTR [ebp+ebx], 0', 'mov BYTE PTR [ebp+ebx+1], 0', 'add ebx, 2'], WDISPATCH))
for op, bits in [(11, 0), (12, 0x3f800000), (13, 0x40000000)]:                  # fconst
    handler([op], f'op_fconst_{op}', lines([f'mov eax, {bits}'], PUSH_INT, DISPATCH))
handler([20], 'op_ldc2_w', lines(['movzx ecx, WORD PTR [esi]', 'xchg cl, ch', f'imul ecx, ecx, {CONSTANT_SIZE}', 'mov edx, [esp]',
    f'add ecx, [edx+{STATE["pool"]}]', 'mov dl, [ecx]', 'cmp dl, 5', 'je @F', 'cmp dl, 6', 'jne exit_op', '@@:',
    f'movq xmm0, QWORD PTR [ecx+{CONSTANT_BITS}]', f'mov eax, [ecx+{CONSTANT_BITS + 4}]', 'movq QWORD PTR [edi+ebx*4], xmm0',
    'mov BYTE PTR [ebp+ebx], 0', 'mov BYTE PTR [ebp+ebx+1], 0', 'add ebx, 2', 'add esi, 2'], WDISPATCH))
A_LO, A_HI, B_LO, B_HI = '[edi+ebx*4-16]', '[edi+ebx*4-12]', '[edi+ebx*4-8]', '[edi+ebx*4-4]'
POP2W = ['sub ebx, 2', TOP]
for op, code in [(97, ['movq xmm0, QWORD PTR ' + A_LO, 'movq xmm1, QWORD PTR ' + B_LO, 'paddq xmm0, xmm1', 'movq QWORD PTR ' + A_LO + ', xmm0']),
                 (101, ['movq xmm0, QWORD PTR ' + A_LO, 'movq xmm1, QWORD PTR ' + B_LO, 'psubq xmm0, xmm1', 'movq QWORD PTR ' + A_LO + ', xmm0']),
                 (127, ['movq xmm0, QWORD PTR ' + A_LO, 'movq xmm1, QWORD PTR ' + B_LO, 'pand xmm0, xmm1', 'movq QWORD PTR ' + A_LO + ', xmm0']),
                 (129, ['movq xmm0, QWORD PTR ' + A_LO, 'movq xmm1, QWORD PTR ' + B_LO, 'por xmm0, xmm1', 'movq QWORD PTR ' + A_LO + ', xmm0']),
                 (131, ['movq xmm0, QWORD PTR ' + A_LO, 'movq xmm1, QWORD PTR ' + B_LO, 'pxor xmm0, xmm1', 'movq QWORD PTR ' + A_LO + ', xmm0']),
                 (105, ['movq xmm7, QWORD PTR ' + B_LO] + ['movq xmm0, QWORD PTR ' + A_LO, 'movdqa xmm1, xmm0', 'pmuludq xmm1, xmm7',
                        'movdqa xmm2, xmm0', 'psrlq xmm2, 32', 'pmuludq xmm2, xmm7', 'movdqa xmm3, xmm7', 'psrlq xmm3, 32', 'pmuludq xmm3, xmm0',
                        'paddq xmm2, xmm3', 'psllq xmm2, 32', 'paddq xmm1, xmm2', 'movq QWORD PTR ' + A_LO + ', xmm1', 'movdqa xmm0, xmm1']),
                 (99, ['movsd xmm0, QWORD PTR ' + A_LO, 'addsd xmm0, QWORD PTR ' + B_LO, 'movsd QWORD PTR ' + A_LO + ', xmm0']),
                 (103, ['movsd xmm0, QWORD PTR ' + A_LO, 'subsd xmm0, QWORD PTR ' + B_LO, 'movsd QWORD PTR ' + A_LO + ', xmm0']),
                 (107, ['movsd xmm0, QWORD PTR ' + A_LO, 'mulsd xmm0, QWORD PTR ' + B_LO, 'movsd QWORD PTR ' + A_LO + ', xmm0']),
                 (111, ['movsd xmm0, QWORD PTR ' + A_LO, 'divsd xmm0, QWORD PTR ' + B_LO, 'movsd QWORD PTR ' + A_LO + ', xmm0'])]:
    handler([op], f'op_wide_{op}', lines(code, POP2W, WDISPATCH))
    fast = [line.replace('movq xmm1, QWORD PTR ' + B_LO, 'movdqa xmm1, xmm7').replace('sd xmm0, QWORD PTR ' + B_LO, 'sd xmm0, xmm7') for line in code]
    if fast != code: handler_w([op], f'op_widew_{op}', lines(fast, POP2W, WDISPATCH))
LMUL_SSE = ['movq xmm0, QWORD PTR ' + A_LO, 'movdqa xmm1, xmm0', 'pmuludq xmm1, xmm7',          # aL*bL
            'movdqa xmm2, xmm0', 'psrlq xmm2, 32', 'pmuludq xmm2, xmm7',                           # aH*bL
            'movdqa xmm3, xmm7', 'psrlq xmm3, 32', 'pmuludq xmm3, xmm0',                           # bH*aL
            'paddq xmm2, xmm3', 'psllq xmm2, 32', 'paddq xmm1, xmm2', 'movq QWORD PTR ' + A_LO + ', xmm1', 'movdqa xmm0, xmm1']
handler_w([105], 'op_lmulw', lines(LMUL_SSE, POP2W, WDISPATCH))   # right operand from xmm7
for op, ins in [(98, 'addss'), (102, 'subss'), (106, 'mulss'), (110, 'divss')]:   # float binary
    handler([op], f'op_float_{op}', lines(['movss xmm0, DWORD PTR [edi+ebx*4-8]', f'{ins} xmm0, DWORD PTR [edi+ebx*4-4]',
        'movss DWORD PTR [edi+ebx*4-8], xmm0'], POP1, DISPATCH))
handler([117], 'op_lneg', lines(['pxor xmm0, xmm0', 'movq xmm1, QWORD PTR [edi+ebx*4-8]', 'psubq xmm0, xmm1', 'movq QWORD PTR [edi+ebx*4-8], xmm0', TOP], WDISPATCH))
handler([119], 'op_dneg', lines(['xor eax, 80000000h', 'mov edx, eax', 'mov eax, [edi+ebx*4-8]'] + store64('[edi+ebx*4-8]') + ['mov eax, edx'], WDISPATCH))
handler([118], 'op_fneg', lines(['xor eax, 80000000h', 'mov [edi+ebx*4-4], eax'], DISPATCH))
# long shifts: value at sp-3/sp-2, int count in eax
SHIFT_PRE = ['mov ecx, eax', 'and ecx, 63', 'mov eax, [edi+ebx*4-12]', 'mov edx, [edi+ebx*4-8]', 'cmp cl, 32']
SHIFT_POST = store64('[edi+ebx*4-12]') + ['dec ebx', 'mov eax, edx']
for op, small, big in [(121, ['shld edx, eax, cl', 'shl eax, cl'], ['mov edx, eax', 'xor eax, eax', 'shl edx, cl']),
                       (123, ['shrd eax, edx, cl', 'sar edx, cl'], ['mov eax, edx', 'sar edx, 31', 'sar eax, cl']),
                       (125, ['shrd eax, edx, cl', 'shr edx, cl'], ['mov eax, edx', 'xor edx, edx', 'shr eax, cl'])]:
    handler([op], f'op_lshift_{op}', lines(SHIFT_PRE, [f'jae lsh_big_{op}'], small, [f'jmp lsh_done_{op}', f'lsh_big_{op}:'],
                                           big, [f'lsh_done_{op}:'], SHIFT_POST, WDISPATCH))   # x86 shifts mask cl to 31
handler([148], 'op_lcmp', lines(['mov eax, ' + A_HI, 'cmp eax, ' + B_HI, 'jl lcmp_lt', 'jg lcmp_gt', 'mov eax, ' + A_LO,
    'cmp eax, ' + B_LO, 'jb lcmp_lt', 'ja lcmp_gt', 'xor eax, eax', 'jmp lcmp_st', 'lcmp_lt:', 'mov eax, -1', 'jmp lcmp_st',
    'lcmp_gt:', 'mov eax, 1', 'lcmp_st:', 'sub ebx, 3', 'mov [edi+ebx*4-4], eax'], DISPATCH))
def fcmp(op, wide, nan):
    load = ['movsd xmm0, QWORD PTR ' + A_LO, 'ucomisd xmm0, QWORD PTR ' + B_LO] if wide else \
           ['movss xmm0, DWORD PTR [edi+ebx*4-8]', 'ucomiss xmm0, DWORD PTR [edi+ebx*4-4]']
    handler([op], f'op_fcmp_{op}', lines(load, [f'jp fcmp_nan_{op}', f'ja fcmp_gt_{op}', f'jb fcmp_lt_{op}', 'xor eax, eax',
        f'jmp fcmp_st_{op}', f'fcmp_nan_{op}:', f'mov eax, {nan}', f'jmp fcmp_st_{op}', f'fcmp_gt_{op}:', 'mov eax, 1',
        f'jmp fcmp_st_{op}', f'fcmp_lt_{op}:', 'mov eax, -1', f'fcmp_st_{op}:', f'sub ebx, {3 if wide else 1}',
        'mov [edi+ebx*4-4], eax'], DISPATCH))
fcmp(149, False, -1); fcmp(150, False, 1); fcmp(151, True, -1); fcmp(152, True, 1)
# conversions
handler([133], 'op_i2l', lines(['cdq'] + store64('[edi+ebx*4-4]') + ['mov BYTE PTR [ebp+ebx], 0', 'inc ebx', 'mov eax, edx'], WDISPATCH))
handler([136], 'op_l2i', lines(POP1, DISPATCH))
handler([135], 'op_i2d', lines(['cvtsi2sd xmm0, eax', 'movsd QWORD PTR [edi+ebx*4-4], xmm0', 'mov BYTE PTR [ebp+ebx], 0', 'inc ebx', TOP], WDISPATCH))
handler([134], 'op_i2f', lines(['cvtsi2ss xmm0, eax', 'movss DWORD PTR [edi+ebx*4-4], xmm0', TOP], DISPATCH))
handler([141], 'op_f2d', lines(['cvtss2sd xmm0, DWORD PTR [edi+ebx*4-4]', 'movsd QWORD PTR [edi+ebx*4-4], xmm0', 'mov BYTE PTR [ebp+ebx], 0', 'inc ebx', TOP], WDISPATCH))
handler([144], 'op_d2f', lines(['cvtsd2ss xmm0, QWORD PTR [edi+ebx*4-8]', 'dec ebx', 'movss DWORD PTR [edi+ebx*4-4], xmm0', TOP], DISPATCH))
handler([142], 'op_d2i', lines(['cvttsd2si ecx, QWORD PTR [edi+ebx*4-8]', 'cmp ecx, 80000000h', 'je exit_op',   # NaN, overflow: C
    'dec ebx', 'mov eax, ecx', 'mov [edi+ebx*4-4], eax'], DISPATCH))
handler([139], 'op_f2i', lines(['cvttss2si ecx, DWORD PTR [edi+ebx*4-4]', 'cmp ecx, 80000000h', 'je exit_op',
    'mov eax, ecx', 'mov [edi+ebx*4-4], eax'], DISPATCH))
handler([138], 'op_l2d', lines(['fild QWORD PTR [edi+ebx*4-8]', 'fstp QWORD PTR [edi+ebx*4-8]', TOP], DISPATCH))   # x87 at 53-bit precision: one rounding

# Returns: the value into state->result and JBV_CORE_RETURN into state->status; C
# unwinds the frame. ireturn of byte/char/short/boolean narrows in C.
CORE_RETURN = 0x52455400
def ret(value):
    return value + ['mov edx, [esp]', 'movd xmm0, eax', f'movq QWORD PTR [edx+{STATE["result"]}], xmm0',   # one 8-byte store: the call site reads 8 bytes
                    f'cmp BYTE PTR [edx+{ACT_ASM}], 0', 'jne ret_core',
                    f'mov DWORD PTR [edx+{STATE["status"]}], {CORE_RETURN}', 'jmp exit_op']
S = STATE
body.append('\n'.join([
    'enter_run:                       ; eax = owner, edx = m, ecx = argbase; [esp] return address, [esp+4] the new activation',
    '    mov ebp, [esp+4]', f'    mov edi, [esp+{8 + ACT_SIZE}]          ; the caller',
    f'    mov [ebp+{ACT_ARGBASE}], ecx', f'    mov [ebp+{ACT_C}], eax', f'    mov [ebp+{ACT_FRAME + F_OWNER}], eax',
    '    mov eax, [eax+8]', f'    mov [ebp+{STATE["pool"]}], eax',
    f'    mov [ebp+{ACT_M}], edx', f'    mov [ebp+{ACT_FRAME + F_METHOD}], edx',
    f'    add ecx, [edi+{ACT_FRAME + F_BASE}]', f'    mov [ebp+{ACT_FRAME + F_BASE}], ecx',   # base
    f'    mov eax, [edi+{STATE["vm"]}]', f'    mov [ebp+{STATE["vm"]}], eax',
    '    push ebx                         ; limits use only eax, ecx, edx, ebx (kept), ebp, edi',
    f'    mov ebx, [eax+{VM_DEPTH}]', f'    cmp ebx, [eax+{VM_MAX_DEPTH}]', '    jae enter_limit',
    '    movzx ebx, WORD PTR [edx+4]', f'    mov [ebp+{ACT_FRAME + F_LOCALS}], ebx', f'    mov [ebp+{STATE["sp"]}], ebx',
    '    movzx ebx, WORD PTR [edx+2]', f'    add ebx, [ebp+{ACT_FRAME + F_LOCALS}]', '    add ebx, ecx',   # base + needed
    f'    cmp ebx, [eax+{VM_MAX_SLOTS}]', '    ja enter_limit',
    f'    sub DWORD PTR [eax+{VM_REMAINING}], 1', '    jc enter_borrow', 'enter_charged:', f'    inc DWORD PTR [eax+{VM_DEPTH}]',
    f'    mov edx, [eax+{VM_USED}]', f'    mov [ebp+{ACT_SAVED}], edx', f'    mov [eax+{VM_USED}], ebx',
    '    pop ebx',
    f'    mov edx, [eax+{VM_SLOTS}]', '    lea edx, [edx+ecx*4]', f'    mov [ebp+{STATE["locals"]}], edx', f'    mov [ebp+{ACT_LOCALS}], edx',
    f'    mov esi, [ebp+{ACT_FRAME + F_LOCALS}]', '    lea edx, [edx+esi*4]', f'    mov [ebp+{ACT_STACK}], edx',
    f'    mov edx, [eax+{VM_REFS}]', '    add edx, ecx', f'    mov [ebp+{STATE["refs"]}], edx', f'    mov [ebp+{ACT_LREFS}], edx',
    '    lea ecx, [edx+esi]', f'    mov [ebp+{ACT_SREFS}], ecx',
    f'    mov ecx, [ebp+{ACT_M}]', '    movzx ecx, WORD PTR [ecx+METHOD_ARGS]',   # uninitialized locals: not references
    'zero_refs:', '    cmp ecx, esi', '    jae zero_done', '    mov BYTE PTR [edx+ecx], 0', '    inc ecx', '    jmp zero_refs', 'zero_done:',
    f'    mov ecx, [eax+{VM_FRAMES}]', f'    mov [ebp+{ACT_FRAME + F_PREV}], ecx', f'    lea ecx, [ebp+{ACT_FRAME}]', f'    mov [eax+{VM_FRAMES}], ecx',
    f'    mov [ebp+{STATE["frame"]}], ecx', '    xor ecx, ecx',
    f'    mov [ebp+{ACT_FRAME + F_PC}], ecx', f'    mov [ebp+{ACT_FRAME + F_SP}], ecx', f'    mov [ebp+{ACT_FRAME + F_MON}], ecx',
    f'    mov [ebp+{STATE["pc"]}], ecx', f'    mov [ebp+{STATE["status"]}], ecx',
    f'    mov esi, [ebp+{ACT_M}]', '    mov ecx, [esi+METHOD_CODE]', f'    mov [ebp+{STATE["code"]}], ecx',
    '    mov ecx, [esi+16]', '    movzx edx, WORD PTR [esi+20]', '    mov cl, [ecx+edx-1]', f'    mov [ebp+{STATE["int_result"]}], cl',
    '    mov cl, [esi+METHOD_RESULT]', f'    mov [ebp+{ACT_KIND}], cl', f'    mov BYTE PTR [ebp+{ACT_ASM}], 1', f'    mov [ebp+{ACT_CALLER}], edi',
    f'    mov ecx, [edi+{STATE["remaining"]}]', f'    mov [ebp+{STATE["remaining"]}], ecx',
    f'    mov ecx, [edi+{STATE["handles"]}]', f'    mov [ebp+{STATE["handles"]}], ecx',
    f'    mov ecx, [edi+{STATE["table"]}]', f'    mov [ebp+{STATE["table"]}], ecx',
    f'    movdqu xmm0, XMMWORD PTR [edi+{STATE["nursery"]}]', f'    movdqu XMMWORD PTR [ebp+{STATE["nursery"]}], xmm0',   # nursery..nursery_size_ref
    f'    movq xmm0, QWORD PTR [edi+{STATE["object_class"]}]', f'    movq QWORD PTR [ebp+{STATE["object_class"]}], xmm0',  # object_class, last_remembered
    '    pop edx', f'    mov [ebp+{ACT_RET}], edx       ; [esp] = the activation; returns go back through ret',
    f'    mov esi, [ebp+{STATE["code"]}]', f'    mov edi, [ebp+{STATE["locals"]}]', f'    mov ebx, [ebp+{STATE["sp"]}]',
    f'    mov ebp, [ebp+{STATE["refs"]}]', '    mov eax, [edi+ebx*4-4]', '    DISPATCH',
    'enter_borrow:                    ; the low word was 0: borrow from the high word, or stop',
    f'    cmp DWORD PTR [eax+{VM_REMAINING + 4}], 0', '    je enter_spent', f'    dec DWORD PTR [eax+{VM_REMAINING + 4}]', '    jmp enter_charged',
    'enter_spent:', f'    mov DWORD PTR [eax+{VM_REMAINING}], 0',
    'enter_limit:', '    pop ebx', f'    mov eax, {CORE_LIMIT}', '    ret',
    'ret_core:                        ; edx = a core activation that returned: unlink it',
    f'    cmp BYTE PTR [edx+{ACT_FRAME + F_MON}], 0', '    jne leave_in_c',
    f'    mov eax, [edx+{STATE["vm"]}]', f'    mov ecx, [edx+{ACT_FRAME + F_PREV}]', f'    mov [eax+{VM_FRAMES}], ecx',
    f'    mov ecx, [edx+{ACT_SAVED}]', f'    mov [eax+{VM_USED}], ecx', f'    dec DWORD PTR [eax+{VM_DEPTH}]', '    xor eax, eax', '    jmp core_return',
    'leave_in_c:', '    mov ecx, edx', '    call @jbv_core_leave@4', '    xor eax, eax',
    'core_return:                     ; eax = status: back to the call site',
    '    mov edx, [esp]', f'    push DWORD PTR [edx+{ACT_RET}]', '    ret',
    'frame_failed:                    ; the callee failed: the caller unwinds (edx = caller, esi past the invoke opcode)',
    f'    mov ebp, [edx+{S["refs"]}]', f'    mov [edx+{S["status"]}], eax', '    jmp exit_op',
    '']))
handler([172], 'op_ireturn', lines(['mov edx, [esp]', f'mov cl, [edx+{STATE["int_result"]}]', "cmp cl, 'I'", 'je ir_go',   # narrow as the descriptor says
    "cmp cl, 'Z'", 'jne @F', 'and eax, 1', 'jmp ir_go', '@@:', "cmp cl, 'B'", 'jne @F', 'movsx eax, al', 'jmp ir_go', '@@:',
    "cmp cl, 'C'", 'jne @F', 'movzx eax, ax', 'jmp ir_go', '@@:', "cmp cl, 'S'", 'jne exit_op', 'movsx eax, ax', 'ir_go:'], ret([])))
handler([176], 'op_areturn', lines(ret([])))
handler([177], 'op_return', lines(ret(['xor eax, eax'])))

out = ['; Generated by tools/gen_interp_x86.py; do not edit.', '; ' + __doc__.strip().splitlines()[0],
       '.686', '.xmm', '.model flat, C', 'option casemap:none', 'option noscoped                 ; handler labels are referenced by op_table', 'PUBLIC jbv_interpret_x86', 'EXTERN SYSCALL @jbv_execute@28:PROC   ; fastcall (/Gr), no C decoration', 'EXTERN SYSCALL @jbv_remember@8:PROC', 'EXTERN SYSCALL @jbv_new@16:PROC', 'EXTERN SYSCALL @jbv_core_leave@4:PROC', 'EXTERN SYSCALL @jbv_core_finish@4:PROC', '',
       'IF JBV_PROFILE_FULL', 'CLASS_COMPONENT EQU 72', 'CLASS_FLAGS EQU 56', 'CLASS_INIT EQU 82', 'CLASS_SLOTS EQU 76', 'METHOD_ACCESSOR EQU 49',
       'METHOD_CODE EQU 28', 'METHOD_ARGS EQU 36', 'METHOD_RESULT EQU 38',
       'ELSE', 'CLASS_COMPONENT EQU 68', 'CLASS_FLAGS EQU 52', 'CLASS_INIT EQU 78', 'METHOD_CODE EQU 24', 'METHOD_ARGS EQU 32', 'METHOD_RESULT EQU 34', 'CLASS_SLOTS EQU 72', 'METHOD_ACCESSOR EQU 45', 'ENDIF', '',
       'DISPATCH_W MACRO', '    movzx ecx, BYTE PTR [esi]', '    inc esi', '    jmp DWORD PTR op_table_w[ecx*4]', 'ENDM', '',
       'DISPATCH MACRO', '    movzx ecx, BYTE PTR [esi]', '    inc esi', '    jmp DWORD PTR op_table[ecx*4]', 'ENDM', '',
       '.const', 'ALIGN 4', 'op_table LABEL DWORD']
import os
OFF = {int(x) for x in os.environ.get('JBV_CORE_OFF', '').split(',') if x}   # bisecting: opcodes left to C
for op in range(256): out.append(f'    DWORD {"exit_op" if op in OFF else handlers.get(op, "exit_op")}')
out += ['op_table_w LABEL DWORD']
for op in range(256): out.append(f'    DWORD {"exit_op" if op in OFF else wide_handlers.get(op, handlers.get(op, "exit_op"))}')
out += ['', '.code',
        '; void jbv_interpret_x86(JbvFastState *state): runs from state->pc until an opcode for C.',
        'jbv_interpret_x86 PROC',
        '    push ebp', '    push ebx', '    push esi', '    push edi',
        '    mov edx, [esp+20]', '    push edx                     ; [esp] = state',
        f'    mov esi, [edx+{STATE["code"]}]', f'    add esi, [edx+{STATE["pc"]}]',
        f'    mov edi, [edx+{STATE["locals"]}]', f'    mov ebp, [edx+{STATE["refs"]}]', f'    mov ebx, [edx+{STATE["sp"]}]',
        '    mov eax, [edi+ebx*4-4]       ; top of stack (a local if the stack is empty: read only)',
        '    DISPATCH',
        'exit_op:                         ; esi is just past the opcode C has to run',
        '    dec esi', '    mov edx, [esp]', '    mov eax, esi', f'    sub eax, [edx+{STATE["code"]}]', f'    mov [edx+{STATE["pc"]}], eax',
        f'    mov [edx+{STATE["sp"]}], ebx', f'    cmp BYTE PTR [edx+{ACT_ASM}], 0', '    jne frame_in_c',
        '    pop edx', '    pop edi', '    pop esi', '    pop ebx', '    pop ebp', '    ret',
        'frame_in_c:                      ; a core activation: C runs it to its end',
        '    mov ecx, edx', '    call @jbv_core_finish@4', '    jmp core_return', '']
out += body
out += cold
at = out.index('PUBLIC jbv_interpret_x86') + 1   # handler names in the MAP, for profiles
out[at:at] = [f'PUBLIC {name}' for name in sorted(set(handlers.values()) | set(wide_handlers.values()))]
out += ['jbv_interpret_x86 ENDP', 'END', '']
(ROOT / 'src/interp_x86.asm').write_text('\n'.join(out), newline='\n')
print(len(handlers), 'opcodes in the x86 core')
