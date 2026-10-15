import sys, math, json
from common import *
PROF=os.path.abspath('../../preview/chrome-profile')
P=8.0; CAP=16.0; S=CAP/0.786; R=4.5
cfg=json.load(open('cfg.json')) if os.path.exists('cfg.json') else {}
S2=cfg.get('s2',S); INDENT=cfg.get('indent',0); G2STROKE=cfg.get('g2stroke',0.0)
GAP=7
C0=4.8
def layout1():
    letters='LDGR'; xs=[];x=0
    for c in letters:
        b=bounds(c); xs.append(x-b[0]*S); x+=(b[2]-b[0])*S+0.03*S
    ext=x-0.03*S
    return xs,ext
xs1,ext1=layout1()
WL=15.0
W1=math.ceil(2*WL+ext1)
# patch 1 height
yb=[2.5*P+i*P for i in range(4)]
low=max(yb[i]-bounds(c)[1]*S for i,c in enumerate('LDGR'))
H=math.ceil(low+0.5*P)
# word 2
it_u,umin,umax=word_layout('Urgent',S2); it_c,cmin,cmax=word_layout('Care',S2)
inkw=max(umax-umin,cmax-cmin+INDENT)
W2=math.ceil(2*WL+inkw)
def pix(v): return v
def build_patch(kind,W,H,uid):
    g2=(kind=='g2')
    paper=(0x1F,0x6F,0x5C) if g2 else (253,252,249)
    sigma=6 if g2 else 5
    uri=texture(int(W*4),int(H*4),paper,sigma,seed=11 if g2 else 7)
    ink='#FFFFFF' if g2 else '#1F6F5C'; rc='#FFFFFF' if g2 else '#1F6F5C'
    ho,vo=(0.25,0.36)
    edge='#175649' if g2 else '#E3E0D8'
    o=[f'<clipPath id="c{uid}"><rect width="{W}" height="{H}" rx="{R}" ry="{R}"/></clipPath>',
       f'<g clip-path="url(#c{uid})"><image width="{W}" height="{H}" preserveAspectRatio="none" xlink:href="{uri}" href="{uri}"/>']
    rules=[];y=4.0
    while y+1<=H-3: rules.append(f'M0 {y:g}H{W}V{y+1:g}H0Z');y+=P
    o.append(f'<path d="{" ".join(rules)}" fill="{rc}" fill-opacity="{ho}"/>')
    v=[]
    for x in (5,8,W-9,W-6): v.append(f'M{x} 0V{H}H{x+1}V0Z')
    o.append(f'<path d="{" ".join(v)}" fill="{rc}" fill-opacity="{vo}"/>')
    d=[]
    if not g2:
        for (c,_),x in zip(zip('LDGR',xs1),xs1):
            pass
        for i,c in enumerate('LDGR'):
            d.append(glyph_path(c,S,WL+xs1[i],yb[i]+0.5))
    else:
        bu=yb[0]+0.5; bc=yb[3]+0.5
        for c,x in it_u: d.append(glyph_path(c,S2,WL-umin+x,bu))
        for c,x in it_c: d.append(glyph_path(c,S2,WL-cmin+INDENT+x,bc))
    st=f' stroke="{ink}" stroke-width="{G2STROKE}" stroke-linejoin="round"' if (g2 and G2STROKE) else ''
    o.append(f'<path d="{" ".join(d)}" fill="{ink}"{st}/></g>')
    o.append(f'<rect x=".5" y=".5" width="{W-1}" height="{H-1}" rx="{R-.5}" ry="{R-.5}" fill="none" stroke="{edge}" stroke-width="1"/>')
    return '\n'.join(o)
HDR='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
def save(name,w,h,body):
    p=f'{name}.svg';open(p,'w').write(HDR.format(w=w,h=h)+f'<title>{name}</title>\n'+body+'\n</svg>');return p
p1=save('header-ldgr',W1,H,build_patch('g1',W1,H,1))
p2=save('header-urgentcare',W2,H,build_patch('g2',W2,H,2))
pw=W1+GAP+W2
pair=f'<g>{build_patch("g1",W1,H,1)}</g><g transform="translate({W1+GAP} 0)">{build_patch("g2",W2,H,2)}</g>'
pp=save('header-pair',pw,H,pair)
for nm,p,w in (('header-ldgr',p1,W1),('header-urgentcare',p2,W2),('header-pair',pp,pw)):
    for k in (1,2,3): render(p,f'{nm}@{k}x.png',w,H,k,PROF)
print(dict(W1=W1,W2=W2,H=H,pair=pw,S=S,S2=S2,ext1=ext1,inkw=inkw))
