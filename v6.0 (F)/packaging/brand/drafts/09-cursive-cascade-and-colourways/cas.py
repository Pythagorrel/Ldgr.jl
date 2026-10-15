import json,sys
fm=json.load(open("metrics.json"))
names=["Petit Formal Script","Dancing Script","Parisienne","Italianno","Rouge Script","Great Vibes","Alex Brush","Pinyon Script"]
def f(x):return round(x,2)
def patch(n,word,mode,gapem=0.03,stepk=1.0):
    g=fm[n]['g'];letters=list(word)
    caps=[g[c]['ymax'] for c in "LDGR"]
    maxcap=max(caps)
    # em layout of ink-left positions
    x=0;pos=[]
    for c in letters:
        gl=g[c];pos.append(x-gl['xmin']);x+=gl['xmax']-gl['xmin']+gapem
    ext=x-gapem
    if mode=="logo":
        s=380.0/ext
    else:
        s=16.0/maxcap
    p=maxcap*s/2
    step=p*stepk
    if mode=="logo":
        c0=0.35*p;gap=4.0;m1=0.7*p;hw,vw,bd=1.25,1.0,1.5
    else:
        c0=0.6*p;gap=3.0;m1=0.9*p;hw,vw,bd=1.0,0.8,1.0
    word_left=c0+gap+m1
    Wd=2*word_left+ext*s
    top_edge=0.0
    yb0=2.5*p if True else 0
    yb=[yb0+i*step for i in range(4)]
    lowest=max(yb[i]-g[c]['ymin']*s for i,c in enumerate(letters))
    H=lowest+0.5*p
    ys=[];y=0.5*p
    while y<H-0.4*p:ys.append(y);y+=p
    xs=[c0,c0+gap,Wd-c0-gap,Wd-c0]
    texts=[dict(text=c,x=word_left+pos[i]*s,y=yb[i]) for i,c in enumerate(letters)]
    # shortfall of cap tops vs rule two above baseline
    sf={c:(2*p-g[c]['ymax']*s)/p for c in letters}
    return dict(W=Wd,H=H,ys=ys,xs=xs,texts=texts,s=s,p=p,cap=g['L']['ymax']*s,maxcap=maxcap*s,border=bd,hw=hw,vw=vw,sf=sf,wl=word_left,ext=ext*s,xh=g['x']['ymax']*s)
def board(cells,cw,rh,mode,ox0=30,oy0=20):
    # cells: list of (font, word, col,row, labelfmt)
    fills=bands=borders=hs=vs="";texts=[];labels=[];info=[]
    for (n,w,c,r) in cells:
        p=patch(n,w,mode);ox=ox0+c*cw;oy=oy0+r*rh
        fills+=f"M{f(ox)} {f(oy)}H{f(ox+p['W'])}V{f(oy+p['H'])}H{f(ox)}Z "
        b=p['border']/2
        borders+=f"M{f(ox+b)} {f(oy+b)}H{f(ox+p['W']-b)}V{f(oy+p['H']-b)}H{f(ox+b)}Z "
        for y in p['ys']:hs+=f"M{f(ox)} {f(oy+y)}H{f(ox+p['W'])} "
        for x in p['xs']:vs+=f"M{f(ox+x)} {f(oy)}V{f(oy+p['H'])} "
        for t in p['texts']:texts.append(dict(text=t['text'],font=n,size=f(p['s']),x=f(ox+t['x']),y=f(oy+t['y'])))
        lab=f"{n} · pitch {p['p']:.1f} · cap {p['maxcap']:.1f} · {w}"
        labels.append(dict(text=lab,x=ox,y=oy+p['H']+(15 if mode=='logo' else 13)))
        info.append((n,w,p))
    return dict(fills=fills.strip(),borders=borders.strip(),hs=hs.strip(),vs=vs.strip(),texts=texts,labels=labels),info
if __name__=="__main__":
    for n in names:
        for w in ("LDGR","Ldgr"):
            a=patch(n,w,"logo");b=patch(n,w,"header")
            print(n,w,"logo W%.0f H%.0f s%.0f p%.1f | hdr W%.0f H%.1f s%.1f p%.1f"%(a['W'],a['H'],a['s'],a['p'],b['W'],b['H'],b['s'],b['p']),{k:round(v,2) for k,v in a['sf'].items()})
