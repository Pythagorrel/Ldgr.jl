// node gen.js header|logo ox oy  -> JSON {W,H,h,v1,v2,band}
const kind=process.argv[2], ox=+process.argv[3]||0, oy=+process.argv[4]||0;
const f=n=>+n.toFixed(2);
let W,H,ys=[],vd=[],dbl=[],band=null;
if(kind==='header'){W=140;H=40;ys=[5.5,15.5,25.5,35.5];
  dbl=[[0.075,0.10],[0.80,0.82]]; vd=[0.89,0.94]; var gap=0;}
else {W=600;H=300;for(let k=0;k<10;k++)ys.push(15+30*k);
  dbl=[[0.06,0.0667],[0.69,0.6967],[0.855,0.8617]]; vd=[0.745,0.80,0.905,0.95]; band=[15,45];}
let h='',v='';
for(const y of ys)h+=`M${f(ox)} ${f(oy+y)}H${f(ox+W)} `;
const xs=[...dbl.flat(),...vd].map(x=>ox+x*W);
for(const x of xs)v+=`M${f(x)} ${f(oy)}V${f(oy+H)} `;
console.log(JSON.stringify({W,H,h:h.trim(),v:v.trim(),band:band?{x:ox,y:oy+band[0],w:W,h:band[1]-band[0]}:null}));
