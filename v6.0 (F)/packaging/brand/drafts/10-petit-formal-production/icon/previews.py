from PIL import Image, ImageDraw
S=[16,20,24,32,40,48,64,96,128,256]
ims={n:Image.open(f'ldgr-{n}.png').convert('RGBA') for n in S}
# icon-sizes: two bands, 1x
pad=24; W=sum(S)+pad*(len(S)+1); H=256+2*pad
out=Image.new('RGBA',(W,H*2),(0,0,0,255))
for bi,bg in enumerate(((243,243,243),(32,32,32))):
    band=Image.new('RGBA',(W,H),bg+(255,)); x=pad
    for n in S:
        band.alpha_composite(ims[n],(x,pad+(256-n)//2)); x+=n+pad
    out.paste(band,(0,bi*H))
out.convert('RGB').save('icon-sizes.png')
# taskbar mock
def strip(bg,line,fg,seed):
    w,h=620,48; im=Image.new('RGBA',(w,h),bg+(255,)); d=ImageDraw.Draw(im)
    d.line((0,0,w,0),fill=line+(255,))
    cols=[(0,120,212),(232,118,0),(60,60,60),(180,40,40),(40,140,90)]
    x=14
    # start button (four squares)
    for dx in (0,8):
        for dy in (0,8): d.rectangle((x+dx,16+dy,x+dx+6,16+dy+6),fill=(0,120,212,255))
    x=56
    items=['g',24,'g',32,'g','g',24,32]
    # show each ldgr size twice among generic tiles
    seq=[('g',0),('g',1),(24,0),('g',2),(32,0),('g',3),('g',4)]
    for k,v in seq:
        if k=='g':
            d.rounded_rectangle((x,12,x+24,12+24),radius=5,fill=cols[v]+(255,)); x+=40
        else:
            im.alpha_composite(ims[k],(x,(h-k)//2+1)); 
            d.rounded_rectangle((x-6,h-5,x+k+5,h-4),radius=1,fill=fg+(255,)) # running indicator
            x+=k+16
    return im
light=strip((243,243,243),(220,220,220),(0,103,192),1); dark=strip((32,32,32),(60,60,60),(96,205,255),2)
t=Image.new('RGBA',(620,48*2+4),(128,128,128,255)); t.paste(light,(0,0)); t.paste(dark,(0,52)); t.convert('RGB').save('icon-taskbar.png')
t.resize((620*3,(48*2+4)*3),Image.NEAREST).convert('RGB').save('_taskbar3x.png')
