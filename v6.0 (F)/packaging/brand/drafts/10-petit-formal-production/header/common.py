import base64, io, subprocess, os, numpy as np
from PIL import Image
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
FONT=TTFont(os.path.expanduser('~/AppData/Local/Microsoft/Windows/Fonts/PetitFormalScript-Regular.ttf'))
UPM=FONT['head'].unitsPerEm; GS=FONT.getGlyphSet(); CM=FONT.getBestCmap(); HM=FONT['hmtx']
def gname(c): return CM[ord(c)]
def bounds(c):
    bp=BoundsPen(GS); GS[gname(c)].draw(bp); return [v/UPM for v in bp.bounds]
def adv(c): return HM[gname(c)][0]/UPM
def glyph_path(c,s,ox,by,stroke=0):
    sp=SVGPathPen(GS,ntos=lambda v:('%.3f'%v).rstrip('0').rstrip('.'))
    GS[gname(c)].draw(TransformPen(sp,(s/UPM,0,0,-s/UPM,ox,by)))
    return sp.getCommands()
def word_layout(word,s,mode='adv'):
    """returns list of (char,pen_x offset) and ink xmin,xmax (px) relative to pen start 0"""
    x=0;items=[];xmin=1e9;xmax=-1e9
    for c in word:
        b=bounds(c); items.append((c,x))
        xmin=min(xmin,x+b[0]*s); xmax=max(xmax,x+b[2]*s)
        x+=adv(c)*s
    return items,xmin,xmax
def texture(w,h,mean,sigma,seed=7,fib=2.5):
    rng=np.random.default_rng(seed)
    def gf(x,sg):
        for ax,sv in enumerate(sg):
            rad=int(4*sv)+1;xs=np.arange(-rad,rad+1);k=np.exp(-xs**2/(2*sv*sv));k/=k.sum()
            x=np.apply_along_axis(lambda v:np.convolve(v,k,mode='same'),ax,x)
        return x
    fine=gf(rng.normal(0,1,(h,w)),(0.7,0.7));fine/=fine.std()
    fb=gf(rng.normal(0,1,(h,w)),(0.6,9));fb/=fb.std()
    t=fine*sigma*1.15+fb*sigma*0.4;t-=t.mean()
    m=np.array(mean,float)
    a=np.clip(m[None,None,:]+t[...,None]*np.array([1,1,1.15]),0,255).round().astype(np.uint8)
    buf=io.BytesIO();Image.fromarray(a).save(buf,'PNG',optimize=True)
    return 'data:image/png;base64,'+base64.b64encode(buf.getvalue()).decode()
CHROME="C:/Program Files/Google/Chrome/Application/chrome.exe"
def render(svgpath,out_png,w,h,dpr,prof):
    """render an svg file at w x h css px, scale dpr, transparent bg -> out_png cropped"""
    d=os.path.dirname(os.path.abspath(out_png))
    html=os.path.join(d,'_r.html')
    open(html,'w').write(f'<!doctype html><html><body style="margin:0;background:transparent"><img src="file:///{os.path.abspath(svgpath).replace(os.sep,"/")}" width="{w}" height="{h}" style="display:block"></body></html>')
    tmp=os.path.join(d,'_r.png')
    subprocess.run([CHROME,'--headless=new','--disable-gpu','--hide-scrollbars','--default-background-color=00000000',f'--force-device-scale-factor={dpr}',f'--window-size={max(w,500)},{max(h,200)}',f'--user-data-dir={prof}',f'--screenshot={tmp}','file:///'+html.replace(os.sep,'/')],check=True,capture_output=True)
    im=Image.open(tmp).convert('RGBA').crop((0,0,round(w*dpr),round(h*dpr)));im.save(out_png);os.remove(tmp);os.remove(html)
