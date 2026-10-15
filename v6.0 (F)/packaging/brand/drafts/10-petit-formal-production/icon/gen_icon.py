import sys, json, math
from common import *
PROF=os.path.abspath('../../preview/chrome-profile')
SIZES=[16,20,24,32,40,48,64,96,128,256]
# per-size tuning
V={16:(None,0),20:(2,0),24:(2,0),32:(3,0),40:(4,2),48:(5,3),64:(7,3),96:(11,4),128:(15,4),256:(29,8)}
T={
 256:dict(tex=1,vert=2,rules='all',stroke=0,col='#1F6F5C',fw=.58,ew=1.5,edge='#E3E0D8',ro=.22,vo=.34),
 128:dict(tex=1,vert=2,rules='all',stroke=0,col='#1F6F5C',fw=.58,ew=1.25,edge='#E3E0D8',ro=.22,vo=.34),
 96 :dict(tex=1,vert=2,rules='all',stroke=0.15,col='#1F6F5C',fw=.60,ew=1,edge='#DAD7CE',ro=.25,vo=.36),
 64 :dict(tex=1,vert=2,rules='all',stroke=0.3,col='#1F6F5C',fw=.60,ew=1,edge='#D3D6CC',ro=.28,vo=.38),
 48 :dict(tex=1,vert=2,rules='all',stroke=0.45,col='#1B6755',fw=.62,ew=1,edge='#CDD3CA',ro=.32,vo=.42),
 40 :dict(tex=0,vert=2,rules='all',stroke=0.6,col='#175649',fw=.62,ew=1,edge='#C3CCC5',ro=.34,vo=.45),
 32 :dict(tex=0,vert=1,rules='all',stroke=0.75,col='#175649',fw=.64,ew=1,edge='#BCC7BF',ro=.34,vo=.5),
 24 :dict(tex=0,vert=1,rules='base',stroke=0.9,col='#175649',fw=.68,ew=1,edge='#B8C4BC',ro=.5,vo=.55),
 20 :dict(tex=0,vert=1,rules='base',stroke=0.95,col='#175649',fw=.70,ew=1,edge='#B8C4BC',ro=.5,vo=.55),
 16 :dict(tex=0,vert=1,rules='base',stroke=1.0,col='#175649',fw=.72,ew=1,edge='#B8C4BC',ro=.5,vo=.55),
}
if os.path.exists('tune.json'):
    for k,v in json.load(open('tune.json')).items(): T[int(k)].update(v)
def icon_svg(N):
    t=T[N]; R=0.20*N
    b=bounds('L')
    vw=1 if N<=96 else N/128 if N<=128 else 2
    ins,gp=V[N]
    xs=([ins] if ins is not None else [])+([ins+gp] if (ins is not None and gp) else [])
    xs=xs+[N-x-vw for x in xs]
    xin=(max(xs[:len(xs)//2])+vw) if xs else 0
    marg=max(0.8,N*0.012)
    fw=min(t['fw'],(N-2*(xin+marg))/N) if xs else t['fw']
    S=fw*N/(b[2]-b[0])
    inkw=(b[2]-b[0])*S; inkh=(b[3]-b[1])*S
    ox=N/2-inkw/2-b[0]*S
    p=0.393*S
    # baseline: ink vertically centred, then snapped so the rule rect is pixel aligned
    yb=N/2+inkh/2+b[1]*S
    if N<=96: yb=round(yb-.5)+.5
    o=[f'<clipPath id="c"><rect width="{N}" height="{N}" rx="{R:g}" ry="{R:g}"/></clipPath><g clip-path="url(#c)">']
    if t['tex']:
        uri=texture(2*N,2*N,(253,252,249),5 if N>=96 else 4,seed=5)
        o.append(f'<image width="{N}" height="{N}" preserveAspectRatio="none" xlink:href="{uri}" href="{uri}"/>')
    else: o.append(f'<rect width="{N}" height="{N}" fill="#FDFCF9"/>')
    rw=max(1,round(N/128)) if N<=128 else N/128
    if N<=64: rw=1
    ys=[]
    if t['rules']=='base': ys=[yb]
    else:
        k=-int((yb)//p)-1
        y=yb-int(yb//p)*p
        while y<N: ys.append(y); y+=p
    rr=' '.join(f'M0 {y-rw/2:.3f}H{N}V{y+rw/2:.3f}H0Z' for y in ys)
    o.append(f'<path d="{rr}" fill="#1F6F5C" fill-opacity="{t["ro"]}"/>')
    vv=' '.join(f'M{x} 0V{N}H{x+vw}V0Z' for x in xs)
    if xs: o.append(f'<path d="{vv}" fill="#1F6F5C" fill-opacity="{t["vo"]}"/>')
    d=glyph_path('L',S,ox,yb)
    st=f' stroke="{t["col"]}" stroke-width="{t["stroke"]}" stroke-linejoin="round"' if t['stroke'] else ''
    o.append(f'<path d="{d}" fill="{t["col"]}"{st}/></g>')
    ew=t['ew']
    o.append(f'<rect x="{ew/2}" y="{ew/2}" width="{N-ew}" height="{N-ew}" rx="{R-ew/2:g}" ry="{R-ew/2:g}" fill="none" stroke="{t["edge"]}" stroke-width="{ew}"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{N}" height="{N}" viewBox="0 0 {N} {N}">'+''.join(o)+'</svg>', dict(fw=round(fw,3),S=round(S,1),inkw=round(inkw,1),inkh=round(inkh,1),yb=yb,xs=xs)
def render_many(items,dpr=1):
    """items: list of (svgfile,N). one page, one chrome call; returns list of PIL images"""
    pad=300; x=10; imgs=[]; pos=[]
    for f,N in items: pos.append((x,10)); x+=N+20
    Wp=x+10
    body=''.join(f'<img src="file:///{os.path.abspath(f).replace(os.sep,"/")}" width="{N}" height="{N}" style="position:absolute;left:{px}px;top:{py}px">' for (f,N),(px,py) in zip(items,pos))
    open('_m.html','w').write(f'<!doctype html><body style="margin:0;background:transparent">{body}</body>')
    subprocess.run([CHROME,'--headless=new','--disable-gpu','--hide-scrollbars','--default-background-color=00000000','--force-device-scale-factor=1',f'--window-size={Wp},320',f'--user-data-dir={PROF}','--screenshot='+os.path.abspath('_m.png'),'file:///'+os.path.abspath('_m.html').replace(os.sep,'/')],check=True,capture_output=True)
    im=Image.open('_m.png').convert('RGBA')
    out=[im.crop((px,py,px+N,py+N)) for (f,N),(px,py) in zip(items,pos)]
    os.remove('_m.png');os.remove('_m.html'); return out
if __name__=='__main__':
    items=[];info={}
    for N in SIZES:
        s,i=icon_svg(N); open(f'ldgr-icon-{N}.svg','w').write(s); items.append((f'ldgr-icon-{N}.svg',N)); info[N]=i
    for (f,N),im in zip(items,render_many(items)): im.save(f'ldgr-{N}.png')
    print(info)
