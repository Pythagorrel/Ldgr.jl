import json,sys
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen
D="C:/Users/jorre/AppData/Local/Microsoft/Windows/Fonts/"
F={"Petit Formal Script":"PetitFormalScript-Regular.ttf","Dancing Script":"DancingScriptwght.ttf","Parisienne":"Parisienne-Regular.ttf","Italianno":"Italianno-Regular.ttf","Rouge Script":"RougeScript-Regular.ttf","Great Vibes":"GreatVibes-Regular.ttf","Alex Brush":"AlexBrush-Regular.ttf","Pinyon Script":"PinyonScript-Regular.ttf"}
out={}
for n,f in F.items():
    t=TTFont(D+f);gs=t.getGlyphSet();cm=t.getBestCmap();u=t['head'].unitsPerEm
    g={}
    for ch in "LDGRldgrx":
        nm=cm[ord(ch)];bp=BoundsPen(gs);gs[nm].draw(bp);b=bp.bounds
        g[ch]=dict(xmin=b[0]/u,ymin=b[1]/u,xmax=b[2]/u,ymax=b[3]/u,adv=gs[nm].width/u)
    # word advances
    def wid(w):return sum(g[c]['adv'] for c in w)
    out[n]=dict(g=g,LDGR_adv=wid("LDGR"),Ldgr_adv=wid("Ldgr"))
    print(n,u,{c:(round(v['ymax'],3),round(v['ymin'],3)) for c,v in g.items()}, round(out[n]['LDGR_adv'],2),round(out[n]['Ldgr_adv'],2))
json.dump(out,open("metrics.json","w"))
