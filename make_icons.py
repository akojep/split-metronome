# Generates the app icons with no third-party libraries.
import struct, zlib, os
def png(size, path):
    bg=(0x11,0x13,0x18); L=(0xff,0x9f,0x43); R=(0x3d,0xd6,0xf5)
    rows=[]
    m=size*0.14; w=size*0.28; gap=size*0.08
    lx0=size/2-gap/2-w; lx1=size/2-gap/2; rx0=size/2+gap/2; rx1=size/2+gap/2+w
    for y in range(size):
        row=bytearray([0])
        for x in range(size):
            c=bg
            if m<=y<size-m:
                if lx0<=x<lx1: c=L
                elif rx0<=x<rx1: c=R
                # tick marks: left side 1 per beat, right side 3 per beat
                if lx0<=x<lx1 and (y-m)%((size-2*m)/2)<size*0.02: c=bg
                if rx0<=x<rx1 and (y-m)%((size-2*m)/6)<size*0.02: c=bg
            row+=bytes(c)
        rows.append(bytes(row))
    raw=b''.join(rows)
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    open(path,'wb').write(data)
here=os.path.dirname(os.path.abspath(__file__))
for s in (180,192,512): png(s, os.path.join(here,'icon-%d.png'%s))
print('icons done')
