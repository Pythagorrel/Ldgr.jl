const H=110, cap=66.4, k=H/cap, g=0.1*H, p=H/2;
const inkL={L:3.9,D:3.9,G:4.1,R:3.9}, inkW={L:51.7,D:62.8,G:62.3,R:61.7};
const order=['L','D','G','R'];
const tL=0.022*H, tB=0.014*H;
const f=v=>+v.toFixed(2);
const rect=(x1,x2,y1,y2)=>`M${f(x1)} ${f(y1)}H${f(x2)}V${f(y2)}H${f(x1)}Z`;
let w=0; order.forEach(c=>w+=inkW[c]*k); w+=3*g;
const X0=Math.round((1200-w)/2), Xend=X0+w, B=244, ext=0.6*H;
const Xs=[];let x=X0;order.forEach(c=>{Xs.push(x);x+=inkW[c]*k+g;});
const letters=order.map((c,i)=>({c,x:f(Xs[i]-k*inkL[c]),y:B,size:f(100*k)}));
const capTop=B-H-tL, capBot=B-H, baseTop=B, baseBot=B+tL;
const cC=B-H-tL/2, cB=B+tL/2; // landmark centres
const wc=B-p;
const lo=X0-ext, hi=Xend+ext;
const out={X0,Xend,B,w,letters,H,tL,tB,wc,lo,hi};
function bdRows(upper,lower,thick){ // backdrop rows, 35% path
  let d='';
  for(let kk=1;kk<=2;kk++){const a=lo+0.5*H*kk,b=hi-0.5*H*kk;
    d+=rect(a,b,cC-p*kk-tB/2,cC-p*kk+tB/2);
    if(lower) d+=rect(a,b,cB+p*kk-tB/2,cB+p*kk+tB/2);}
  return d;}
// V1
out.v1={ hi:rect(lo,hi,capTop,capBot)+rect(lo,hi,baseTop,baseBot), bd:bdRows(1,1), wRect:rect(lo,hi,wc-tL/2,wc+tL/2),
  red: rect(X0-0.5*H-0.0155*H*0-(0.03*H/2+0.014*H),X0-0.5*H-0.03*H/2,capTop,baseBot)+rect(X0-0.5*H+0.03*H/2,X0-0.5*H+0.03*H/2+0.014*H,capTop,baseBot)};
// V2: faint everything
const cellPad=0.25*g; let hl='',cx=X0;
order.forEach((c,i)=>{const a=Xs[i]-cellPad,b=Xs[i]+inkW[c]*k+cellPad; hl+=rect(a,b,capTop,capBot)+rect(a,b,baseTop,baseBot);});
out.v2={ hl, bd:bdRows(1,1)+rect(lo,hi,cC-tB/2,cC+tB/2)+rect(lo,hi,cB-tB/2,cB+tB/2), wRect:rect(lo,hi,wc-tB/2,wc+tB/2)};
// V3
const tw=tL, gp=0.05*H, yc=B+p, a3=X0-0.15*H, b3=Xend+0.15*H;
out.v3={ hi:out.v1.hi, bd:bdRows(1,0), wRect:out.v1.wRect,
  tot: rect(a3,b3,yc-gp/2-tw,yc-gp/2)+rect(a3,b3,yc+gp/2,yc+gp/2+tw)};
out.cellPad=cellPad;
console.log(JSON.stringify(out,null,1));
