import json,sys
from gen import *
kind=sys.argv[1]
fn=header if kind=="header" else logo
colx=[30,230] if kind=="header" else [40,480]
rowh=80 if kind=="header" else 250
y0=20
fills="";bands="";borders="";hs="";vs="";texts=[];labels=[];rects=[]
for i,n in enumerate(names):
    for j,w in enumerate(("LDGR","Ldgr")):
        p=fn(n,w);ox=colx[j];oy=y0+i*rowh
        Wd,Hd=p['W'],p['H']
        rects.append((ox,oy,Wd,Hd))
        fills+=f"M{f(ox)} {f(oy)}H{f(ox+Wd)}V{f(oy+Hd)}H{f(ox)}Z "
        b=p['border']/2
        borders+=f"M{f(ox+b)} {f(oy+b)}H{f(ox+Wd-b)}V{f(oy+Hd-b)}H{f(ox+b)}Z "
        if p['band']:
            a,c=p['band'];bands+=f"M{f(ox)} {f(oy+a)}H{f(ox+Wd)}V{f(oy+c)}H{f(ox)}Z "
        for y in p['ys']:hs+=f"M{f(ox)} {f(oy+y)}H{f(ox+Wd)} "
        for x in p['xs']:vs+=f"M{f(ox+x)} {f(oy)}V{f(oy+Hd)} "
        texts.append(dict(text=w,font=n,size=f(p['s']),x=f(ox+p['xo']),y=f(oy+p['yb']),n=n,w=w))
        if kind=="header":
            lab=f"{n} · pitch {p['P']:.1f} pt · cap {p['cap']:.1f} pt"
            labels.append(dict(text=lab,x=ox,y=oy+Hd+14))
        else:
            lab=f"{n} · pitch {p['P']:.1f} · cap {p['cap']:.0f} · {p['rows']} rows"
            labels.append(dict(text=lab,x=ox,y=oy+Hd+18))
last=rowh*8+y0
out=dict(rects=rects,fills=fills.strip(),bands=bands.strip(),borders=borders.strip(),hs=hs.strip(),vs=vs.strip(),texts=texts,labels=labels,height=last,width=(colx[1]+230 if kind=="header" else colx[1]+420))
json.dump(out,open(f"board-{kind}.json","w"))
print(len(fills),len(hs),len(vs),out['width'],out['height'])
