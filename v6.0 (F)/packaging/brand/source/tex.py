import numpy as np
from PIL import Image, ImageDraw, ImageFilter
W,H=470.53,237.74; R=16.5
k=2048/W; w=2048; h=round(H*k); r=R*k
rng=np.random.default_rng(7)
n=rng.normal(0,1,(h,w))
def gaussian_filter(x,sig):
    import numpy as np
    sg=(sig,sig) if not isinstance(sig,tuple) else sig
    # separable gaussian via numpy convolution
    for ax,sv in enumerate(sg):
        rad=int(4*sv)+1;xs=np.arange(-rad,rad+1);kk=np.exp(-xs**2/(2*sv*sv));kk/=kk.sum()
        x=np.apply_along_axis(lambda v:np.convolve(v,kk,mode='same'),ax,x)
    return x
fine=gaussian_filter(n,0.7); fine/=fine.std()
# faint horizontal fibres
fib=gaussian_filter(rng.normal(0,1,(h,w)),(0.6,9)); fib/=fib.std()
t=fine*7.0+fib*2.5
t-=t.mean()
mean=np.array([253,252,249.0])
base=mean[None,None,:]+t[...,None]*np.array([1,1,1.15])
off=0.0
for _ in range(30):
    a=np.clip(base+off,0,255)
    off+=(mean-a.reshape(-1,3).mean(0))[None,None,:]*1.0
a=np.clip(base+off,0,255).round().astype(np.uint8)
# rounded alpha, 4x supersampled
S=4
m=Image.new("L",(w*S,h*S),0);ImageDraw.Draw(m).rounded_rectangle((0,0,w*S-1,h*S-1),radius=r*S,fill=255)
m=m.resize((w,h),Image.LANCZOS)
im=Image.fromarray(a).convert("RGBA");im.putalpha(m);im.save("tex-g1.png")
print(w,h,a.reshape(-1,3).mean(0),a.std())
