import json
fm=json.load(open("metrics.json"))
names=["Petit Formal Script","Dancing Script","Parisienne","Italianno","Rouge Script","Great Vibes","Alex Brush","Pinyon Script"]
# (bx,by,bw,bh) of outlines at size 100, origin x 50/650, baseline 150*(i+1)
VC=[((50,71.435546875,367.431640625,104.248046875),(650,66.40625,265.52734375,109.326171875)),
((42.6,228.0,241.6,84.1),(642.6,228.0,187.3,100.0)),
((50.9765625,377.5390625,362.5,93.5546875),(650.9765625,378.759765625,200.1953125,115.771484375)),
((50.3,545.1,239.6,89.7),(650.3,538.8,142.8,96.2)),
((47.28,682.88,251.44,100.64),(647.28,683.52,150.88,98.4)),
((49.7,817.8,358.8,119.8),(649.7,820.9,181.7,111.0)),
((50.3,982.1,331.6,83.3),(650.3,982.1,192.7,88.4)),
((50.0,1129.6875,298.388671875,71.533203125),(650.0,1122.119140625,203.90625,116.30859375))]
W={}
for i,n in enumerate(names):
    B=150*(i+1)
    for j,(word,ox) in enumerate((("LDGR",50),("Ldgr",650))):
        bx,by,bw,bh=VC[i][j]
        W[(n,word)]=dict(xoff=(bx-ox)/100,w=bw/100,top=(B-by)/100,bot=(by+bh-B)/100)
def f(x):return round(x,2)
INK="#1C2521"
CAP=16.0
def header(n,word):
    d=W[(n,word)];g=fm[n]['g']
    s=CAP/g['L']['ymax'];P=d['top']*s
    H=46.0;yb=26.0
    xl=20.0
    x_origin=xl-d['xoff']*s
    xr=xl+d['w']*s+8
    Wd=xr+28
    ys=[];y=yb
    while y-P>0.5:y-=P
    while y<H-0.5:ys.append(y);y+=P
    xs=[10,13.5,xr,xr+2.8,xr+12.6,xr+19.6]
    return dict(W=Wd,H=H,ys=ys,xs=xs,band=None,s=s,P=P,yb=yb,xo=x_origin,cap=CAP,border=1.0,hw=1.0,vw=0.8)
def logo(n,word):
    d=W[(n,word)];g=fm[n]['g']
    top=d['top'];wf=d['w'];R=1.65
    best=None
    for rows in (6,7):
        Wu=2*(rows+1)*top           # em units, P=top
        lx2=0.89*top
        G1=lx2+R*wf
        share=(Wu-G1)/Wu
        score=abs(share-0.31)
        if best is None or score<best[0]:best=(score,rows,Wu,share)
    _,rows,Wu,share=best
    k=400.0/Wu
    P=top*k;Wd=400.0;Hd=200.0
    ys=[0.5*P+i*P for i in range(rows+1)]
    lx1=0.8*P;lx2=0.89*P
    w=wf*k
    G1=lx2+R*w
    wl=lx2+0.3*(R-1)*w
    xo=wl-d['xoff']*k
    end=Wd-0.8*P
    fr=[0,0.026,0.21,0.42,0.635,0.66,0.827,1.0]
    xs=[lx1,lx2]+[G1+(end-G1)*x for x in fr]
    return dict(W=Wd,H=Hd,ys=ys,xs=xs,band=(ys[0],ys[1]),s=k,P=P,yb=ys[4],xo=xo,cap=g['L']['ymax']*k,rows=rows,r=R,share=share,xl=wl,xend=wl+w,border=1.5,hw=1.25,vw=1.0)
if __name__=="__main__":
    for n in names:
        for w in ("LDGR","Ldgr"):
            h=header(n,w);l=logo(n,w)
            print(n,w,"hdr s=%.1f P=%.1f W=%.0f"%(h['s'],h['P'],h['W']),"| logo rows=%d share=%.2f s=%.0f P=%.1f cap=%.0f word %.0f-%.0f G1=%.0f"%(l['rows'],l['share'],l['s'],l['P'],l['cap'],l['xl'],l['xend'],l['xs'][2]))
