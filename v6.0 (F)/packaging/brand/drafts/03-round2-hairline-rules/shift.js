const g=require('./geom2.json');
const sh=(d,dx)=>d.replace(/([MHV])(-?[\d.]+)( (-?[\d.]+))?/g,(m,c,a,_,b)=>{
 if(c==='M') return `M${+(+a+dx).toFixed(2)} ${b}`; if(c==='H') return `H${+(+a+dx).toFixed(2)}`; return m;});
const o={};
o.v1hi=sh(g.v1.hi,0);o.v1bd=g.v1.bd;o.v1red=g.v1.red;
o.v2hl=sh(g.v2.hl,2440);o.v2bd=sh(g.v2.bd,2440);
o.v3hi=sh(g.v3.hi,4880);o.v3bd=sh(g.v3.bd,4880);o.v3tot=sh(g.v3.tot,4880);
console.log(JSON.stringify(o,null,1));
