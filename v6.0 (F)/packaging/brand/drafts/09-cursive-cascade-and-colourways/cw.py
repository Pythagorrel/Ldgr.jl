import json
from cas import *
fonts=["Dancing Script","Petit Formal Script"]
out={}
# layout: (mode,font,y)
rows=[("logo",fonts[0],30),("logo",fonts[1],420),("header",fonts[0],720),("header",fonts[1],800)]
for col,ox0 in (("g1",30),("g2",600)):
    for mode in ("logo","header"):
        d=dict(fill="",border="",hs="",vs="",texts=[],labels=[],rects="")
        for (m,n,oy) in rows:
            if m!=mode:continue
            p=patch(n,"LDGR",m);ox=ox0
            d['fill']+=f"M{f(ox)} {f(oy)}H{f(ox+p['W'])}V{f(oy+p['H'])}H{f(ox)}Z "
            b=p['border']/2
            d['border']+=f"M{f(ox+b)} {f(oy+b)}H{f(ox+p['W']-b)}V{f(oy+p['H']-b)}H{f(ox+b)}Z "
            for y in p['ys']:d['hs']+=f"M{f(ox)} {f(oy+y)}H{f(ox+p['W'])} "
            for x in p['xs']:d['vs']+=f"M{f(ox+x)} {f(oy)}V{f(oy+p['H'])} "
            for t in p['texts']:d['texts'].append(dict(text=t['text'],font=n,size=f(p['s']),x=f(ox+t['x']),y=f(oy+t['y'])))
            d['labels'].append((n,m,ox,oy,p['W'],p['H']))
        out[(col+"-"+mode)]=d
json.dump(out,open("cw.json","w"))
for k,v in out.items():
    print("==",k);print("FILL",v['fill']);print("BORDER",v['border']);print("HS",v['hs']);print("VS",v['vs'])
    for t in v['texts']:print(json.dumps(t))
    print(v['labels'])
