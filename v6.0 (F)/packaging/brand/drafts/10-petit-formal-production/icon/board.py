from PIL import Image
import sys
S=[16,20,24,32,40,48,64,96,128,256]
def board(out,bgs=((243,243,243),(32,32,32))):
    ims=[Image.open(f'ldgr-{n}.png') for n in S]
    w=sum(n+20 for n in S[:-1])+20+256+20  # row 1x
    # row A: 1x ; row B: 8x for <=32 ; 
    rows=[]
    Z=[(16,8),(20,8),(24,8),(32,8),(40,6),(48,5)]
    wz=sum(n*z+16 for n,z in Z)+16
    b=Image.new('RGBA',(max(wz,1500),310+2*60),(243,243,243,255))
    x=16
    for (n,z),i in zip(Z,ims): 
        im=i.resize((n*z,n*z),Image.NEAREST);b.alpha_composite(im,(x,12));x+=n*z+16
    b.save(out)
board(sys.argv[1])
