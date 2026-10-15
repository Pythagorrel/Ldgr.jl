import re,sys,os
sys.path.insert(0,r'C:/Users/jorre/AppData/Local/Temp/claude/E--Ldgr/3da7f582-9a49-4fc0-9da5-44332cbe25ab/scratchpad/brand/final3/header')
from common import *
SP=r'C:/Users/jorre/AppData/Local/Temp/claude/E--Ldgr/3da7f582-9a49-4fc0-9da5-44332cbe25ab/scratchpad/brand'
OUT=SP+'/final6/header'
STROKE=float(os.environ.get('STROKE',0.3)); LS=float(os.environ.get('LS',1.12)); M=float(os.environ.get('M',8))
DT,DB,RT,RB=12.507,28.898,28.507,44.898   # ink extremes of D and R (outline)
YU=DT+(DB-DT)*2/7+float(os.environ.get('UOFF',0.1)); YC=RT+(RB-RT)*4/9
h=STROKE/2
# ink top = BU-0.786S-h = YU ; ink bottom = BC+0.019S+h = YC ; BC-BU = LS*S
S=(YC-YU-2*h)/(0.786+0.019+LS)
BU=YU+h+0.786*S; BC=BU+LS*S
YU0=DT+(DB-DT)*2/7
a=open(SP+'/final4/header/header-ldgr.svg').read(); b=open(SP+'/final4/header/header-urgentcare.svg').read()
img=lambda s: re.search(r'<image[^>]*/>',s).group(0)
paths=lambda s: re.findall(r'<path d="([^"]*)"([^>]*)/>',s)
ga=paths(a); 
letters=[p for p in ga if 'stroke-width="0.45"' in p[1]][0]
J=101  # junction x
it_u,u0,u1=word_layout('Urgent',S); it_c,c0,c1=word_layout('Care',S)
inner=round(u1-u0+2*M); L=103; RL=L+inner   # right-hand line x
W=RL+9
ux=L+(inner-(u1-u0))/2-u0
CARE_DX=float(os.environ.get('CARE_DX',(u1-u0-(c1-c0))/2))
cx=ux+u0+CARE_DX-c0
def word(items,ox,by): return ' '.join(glyph_path(c,S,ox+dx,by) for c,dx in items)
txt=word(it_u,ux,BU)+' '+word(it_c,cx,BC)
R=4.5
rules=lambda x0,x1:' '.join(f'M{x0} {y} L{x1} {y} L{x1} {y+1} L{x0} {y+1} Z' for y in range(4,49,8))
vl=lambda xs:' '.join(f'M{x} 0 L{x} 49 L{x+1} 49 L{x+1} 0 Z' for x in xs)
imgL=img(a)
imgG=img(b).replace('matrix(0.25 0 0 0.25 0 0)',f'matrix(0.25 0 0 0.25 {J} 0)')
clip=f'M{R} 0 L{W-R} 0 C{W-R+2.485} 0 {W} 2.015 {W} {R} L{W} {49-R} C{W} {49-R+2.485} {W-R+2.485} 49 {W-R} 49 L{R} 49 C2.015 49 0 {49-R+2.485} 0 {49-R} L0 {R} C0 2.015 2.015 0 {R} 0 Z'
k=0.5523*4
edgeL=f'M{J} 0.5 L{R} 0.5 C2.291 0.5 0.5 2.291 0.5 {R} L0.5 44.5 C0.5 46.709 2.291 48.5 {R} 48.5 L{J} 48.5'
edgeG=f'M{J} 0.5 L{W-R} 0.5 C{W-R+2.209} 0.5 {W-0.5} 2.291 {W-0.5} {R} L{W-0.5} 44.5 C{W-0.5} 46.709 {W-R+2.209} 48.5 {W-R} 48.5 L{J} 48.5'
svg=f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="49" viewBox="0 0 {W} 49">
  <defs>
    <clipPath id="clip-all"><path d="{clip}"/></clipPath>
    <clipPath id="clip-L"><rect x="0" y="0" width="{J}" height="49"/></clipPath>
    <clipPath id="clip-G"><rect x="{J}" y="0" width="{W-J}" height="49"/></clipPath>
  </defs>
  <title>header.svg</title>
  <g clip-path="url(#clip-all)">
    <g clip-path="url(#clip-L)">
      {imgL}
      <path d="{rules(0,J)}" fill="#1f6f5c" fill-opacity="0.25"/>
      <path d="{vl([5,8,99])}" fill="#1f6f5c" fill-opacity="0.36"/>
      <path d="{letters[0]}"{letters[1]}/>
    </g>
    <g clip-path="url(#clip-G)">
      {imgG}
      <path d="{rules(J,W)}" fill="#ffffff" fill-opacity="0.25"/>
      <path d="{vl([102,RL,RL+3])}" fill="#ffffff" fill-opacity="0.36"/>
      <path d="{txt}" fill="#ffffff" stroke="#ffffff" stroke-width="{STROKE}" stroke-linejoin="round"/>
    </g>
  </g>
  <path d="{edgeL}" fill="none" stroke="#e3e0d8"/>
  <path d="{edgeG}" fill="none" stroke="#175649"/>
</svg>'''
open(OUT+'/header.svg','w').write(svg)
print('S',S,'BU',BU,'BC',BC,'YU',YU,'YC',YC,'W',W,'inner',inner,'ux',ux,'cx',cx)
prof=SP+'/preview/chrome-profile'
for name,d in [('1x',1),('1.25x',1.25),('1.5x',1.5),('2x',2),('3x',3)]:
    render(OUT+'/header.svg',f'{OUT}/header@{name}.png',W,49,d,prof)
