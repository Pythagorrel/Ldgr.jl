const fs=require('fs');
const SP=process.argv[2];
const logo=fs.readFileSync(SP+'/final/ldgr-logo.svg','utf8');
const ds=[...logo.matchAll(/<path d="([^"]+)" fill="#1c2521"/g)].map(m=>m[1]);
const A=90.75,B=524.36,CAP=139.48,BASE=249.48,H=110;
// highlight cells (logo units)
const cells=[[90.75,181.9],[187.4,296.93],[302.43,411.14],[416.64,524.36]];
// waist fragments in logo art units; outer flags
const waist=[[27.5,103.4],[133.5,200],[230.2,266.6],[332.9,357.1],[412.8,429.2],[501.5,587.61]];
const f=n=>+n.toFixed(2);
function variant(name,h,rows,hl,faintOp,faintW,clear){
  const s=h/H, pitch=h/2, ext=0.6*h;
  const inkW=(B-A)*s;
  const W=Math.ceil(2*ext+inkW+2), x0=(W-inkW)/2; // x of A
  const T=1+faintW*0+rows*pitch+1; // cap top (outer rule above takes 1px)
  const Hh=T+h+rows*pitch+1+1;
  const X=x=>x0+(x-A)*s;
  const tx=(d)=>d.replace(/([MLCZ])([^MLCZ]*)/g,(m,c,r)=>{const n=r.trim()?r.trim().split(/[\s,]+/).map(Number):[];let o=c;for(let i=0;i<n.length;i+=2)o+=(i?' ':'')+f(X(n[i]))+' '+f(T+(n[i+1]-CAP)*s);return o+' ';}).trim();
  const rect=(x1,x2,y,t)=>`M${f(x1)} ${f(y)}H${f(x2)}V${f(y+t)}H${f(x1)}Z`;
  let faint='';
  const capRuleY=T-faintW, baseRuleY=T+h;
  faint+=rect(x0-ext,x0+inkW+ext,capRuleY,faintW)+rect(x0-ext,x0+inkW+ext,baseRuleY,faintW);
  for(let k=1;k<=rows;k++){
    const e=k==1?0.075*h:-0.425*h; // beyond highlight ends (negative = inside)
    faint+=rect(x0-e,x0+inkW+e,capRuleY-k*pitch,faintW)+rect(x0-e,x0+inkW+e,baseRuleY+k*pitch,faintW);
  }
  // waist
  const wy=T+h/2, trim=Math.max(0,clear-4.4*s);
  waist.forEach(([a,b],i)=>{
    let p=X(a),q=X(b);
    if(i==0)p=x0-ext; else p+=trim;
    if(i==waist.length-1)q=x0+inkW+ext; else q-=trim;
    if(q-p>=3) faint+=rect(p,q,wy,faintW);
  });
  let hs='';
  cells.forEach(([a,b])=>{const p=X(a),q=X(b);hs+=rect(p,q,T-hl,hl)+rect(p,q,T+h,hl);});
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${Hh}" viewBox="0 0 ${W} ${Hh}">
<title>LDGR ${name}</title>
<path d="${faint}" fill="#1F6F5C" fill-opacity="${faintOp}"/>

${ds.map(d=>`<path d="${tx(d)}" fill="#1C2521"/>`).join('\n')}
</svg>
`;
  fs.writeFileSync(`${SP}/header2/${name}.svg`,svg);
  console.log(name,W,Hh,'T',T,'waistpieces');
}
const o=JSON.parse(process.argv[3]||'{}');
variant('w1',18,1,o.hl1||1.75,o.op||0.5,1,1.5);
variant('w2',20,1,o.hl2||2,o.op||0.5,1,1.5);
variant('w3',16,2,o.hl3||1.5,o.op||0.5,1,1.5);
