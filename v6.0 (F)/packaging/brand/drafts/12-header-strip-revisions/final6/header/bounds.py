import re,numpy as np
a=open('final4/header/header-ldgr.svg').read()
L=[p for p in re.findall(r'<path d="([^"]*)"([^>]*)/>',a) if 'stroke-width="0.45"' in p[1]][0][0]
subs=re.findall(r'M[^M]*',L)
def bez(p0,p1,p2,p3):
    t=np.linspace(0,1,400)[:,None]
    return (1-t)**3*p0+3*(1-t)**2*t*p1+3*(1-t)*t*t*p2+t**3*p3
out=[]
for s in subs:
    toks=re.findall(r'[MCLZ]|-?[\d.]+',s); i=0; pts=[]; cur=None
    while i<len(toks):
        c=toks[i]
        if c=='M' or c=='L': cur=np.array([float(toks[i+1]),float(toks[i+2])]); pts.append(cur); i+=3
        elif c=='C':
            v=[float(x) for x in toks[i+1:i+7]]; p=[np.array(v[0:2]),np.array(v[2:4]),np.array(v[4:6])]
            pts+=list(bez(cur,*p)); cur=p[2]; i+=7
        else: i+=1
    P=np.array(pts); out.append((P[:,0].min(),P[:,0].max(),P[:,1].min(),P[:,1].max()))
for o in out: print(['%.3f'%v for v in o])
