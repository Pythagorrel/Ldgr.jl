import json,sys
from cas import *
which=sys.argv[1]
if which=="logo":
    cells=[(n,"LDGR",i%2,i//2) for i,n in enumerate(names)];b,info=board(cells,540,390,"logo")
elif which=="logoL":
    top=sys.argv[2].split(",");cells=[(n,"Ldgr",i%2,i//2) for i,n in enumerate(top)];b,info=board(cells,560,450,"logo")
elif which=="header":
    top=sys.argv[2].split(",");cells=[(n,"LDGR",i%2,i//2) for i,n in enumerate(top)];b,info=board(cells,170,86,"header",20,16)
json.dump(b,open(f"b-{which}.json","w"))
for k in("fills","borders","hs","vs"):print(k,len(b[k]))
print(len(b['texts']))
