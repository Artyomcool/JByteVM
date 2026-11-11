"""Drop only verifier stack maps from the VM's embedded, trusted class library.

The javac output on disk remains intact for tools. Code, exception handlers,
reflection attributes and constant pool entries are preserved byte for byte.
The resulting image is intended for JByteVM, which has no bytecode verifier.
"""
import struct


def without_stack_maps(data):
    pos=10
    utf={}
    count=struct.unpack_from('>H',data,8)[0]
    index=1
    while index<count:
        tag=data[pos];pos+=1
        if tag==1:
            size=struct.unpack_from('>H',data,pos)[0];pos+=2
            utf[index]=data[pos:pos+size];pos+=size
        elif tag in (5,6):pos+=8;index+=1
        else:pos+={3:4,4:4,7:2,8:2,9:4,10:4,11:4,12:4,15:3,16:2,17:4,18:4,19:2,20:2}[tag]
        index+=1

    def attributes(offset,code=False):
        total=struct.unpack_from('>H',data,offset)[0];offset+=2
        result=[]
        for _ in range(total):
            name,size=struct.unpack_from('>HI',data,offset);offset+=6
            end=offset+size
            if code and utf[name]==b'StackMapTable':offset=end;continue
            body=data[offset:end]
            if utf[name]==b'Code':
                at=offset+8+struct.unpack_from('>I',data,offset+4)[0]
                at+=2+8*struct.unpack_from('>H',data,at)[0]
                nested,after=attributes(at,True)
                if after!=end:raise ValueError('Invalid Code attribute')
                body=data[offset:at]+nested
            result.append(struct.pack('>HI',name,len(body))+body);offset=end
        return struct.pack('>H',len(result))+b''.join(result),offset

    pos+=6
    pos+=2+2*struct.unpack_from('>H',data,pos)[0]
    output=[data[:pos]]
    for _ in range(2): # fields, then methods
        members=struct.unpack_from('>H',data,pos)[0]
        output.append(data[pos:pos+2]);pos+=2
        for _ in range(members):
            output.append(data[pos:pos+6]);pos+=6
            body,pos=attributes(pos);output.append(body)
    body,pos=attributes(pos);output.append(body)
    if pos!=len(data):raise ValueError('Invalid class image')
    return b''.join(output)
