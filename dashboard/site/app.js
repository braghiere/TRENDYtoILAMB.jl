"use strict";
const CMAPS={
  viridis:[[68,1,84],[72,40,120],[62,74,137],[49,104,142],[38,130,142],[31,158,137],[53,183,121],[109,205,89],[180,222,44],[253,231,37]],
  turbo:[[48,18,59],[70,107,227],[41,175,208],[27,229,134],[164,252,59],[251,181,26],[229,86,15],[122,4,3]],
  magma:[[0,0,4],[40,11,84],[101,21,110],[159,42,99],[212,72,66],[245,125,21],[250,193,39],[252,253,191]],
  plasma:[[13,8,135],[84,2,163],[139,10,165],[185,50,137],[219,92,104],[244,136,73],[254,188,43],[240,249,33]],
  RdBu:[[5,48,97],[33,102,172],[67,147,195],[146,197,222],[209,229,240],[247,247,247],[253,219,199],[244,165,130],[214,96,77],[178,24,43],[103,0,31]],
  RdYlBu:[[49,54,149],[69,117,180],[116,173,209],[171,217,233],[224,243,248],[255,255,191],[254,224,144],[253,174,97],[244,109,67],[215,48,39],[165,0,38]],
};
const DIVERGING=new Set(["RdBu","RdYlBu"]);
function lutColor(a,t){t=t<0?0:t>1?1:t;const x=t*(a.length-1),k=x|0,f=x-k,p=a[k],q=a[Math.min(k+1,a.length-1)];return[p[0]+(q[0]-p[0])*f,p[1]+(q[1]-p[1])*f,p[2]+(q[2]-p[2])*f];}

let M,GM,OBS={},RMSE=null,LAND,T=0,playing=null,disp=null,SCEN="S2";
let projName="equalEarth",PX=null,PY=null,MW=0,MH=0,rot=[0,-15],DPR=1;
let region=null,regionPix=null,COSLAT=null,CELLA=null;
let IC=null;                                   // last intercomp layout, for hover tooltip
const GMKIND={gpp:"flux",nbp:"flux",npp:"flux",ra:"flux",rh:"flux",reco:"flux",fFire:"flux",cVeg:"pool",cSoil:"pool",cLitter:"pool"};
const gmKind=v=>GMKIND[v]||"mean";
const NAMES={gpp:"Gross Primary Production",npp:"Net Primary Production",nbp:"Net Biome Production",
  ra:"Autotrophic Respiration",rh:"Heterotrophic Respiration",reco:"Ecosystem Respiration",
  cVeg:"Vegetation Carbon",cSoil:"Soil Carbon",cLitter:"Litter Carbon",lai:"Leaf Area Index",
  et:"Evapotranspiration",tran:"Transpiration",mrro:"Runoff",mrso:"Soil Moisture",
  pr:"Precipitation",tas:"Near-Surface Air Temperature",rsds:"Surface Downward Shortwave",fFire:"Fire Carbon Flux"};
const vlabel=v=>NAMES[v]||v.toUpperCase();                    // full name for plot titles
const vaxis=v=>vlabel(v)+" ("+(vmeta(v)?vmeta(v).units:"")+")";
const gmUnits=v=>{const k=gmKind(v);return k==="flux"?"Pg C yr⁻¹":k==="pool"?"Pg C":vmeta(v).units;};
const cache={},climCache={},trendCache={},$=id=>document.getElementById(id);
const key=(v,l)=>v+"|"+l,vmeta=n=>M.variables.find(v=>v.name===n);
const curVar=()=>$("variable").value,curLayer=()=>$("model").value,curMode=()=>$("mode").value;
const PROJS={equalEarth:()=>d3.geoEqualEarth(),naturalEarth1:()=>d3.geoNaturalEarth1(),robinson:()=>d3.geoRobinson(),
  mollweide:()=>d3.geoMollweide(),equirectangular:()=>d3.geoEquirectangular(),orthographic:()=>d3.geoOrthographic().rotate(rot.slice())};
let _raf=null;function scheduleGlobe(){if(_raf)return;_raf=requestAnimationFrame(()=>{_raf=null;setupMap();render();drawCoast();});}
const OFF=document.createElement("canvas");

async function boot(){
  setBoot("manifest…",15);await loadScenarioData("S2");
  setBoot("coastlines…",35);const topo=await(await fetch("vendor/land-110m.json")).json();LAND=topojson.feature(topo,topo.objects.land);
  COSLAT=M.lat.map(l=>Math.cos(l*Math.PI/180));
  {const R=6.371e6,d=Math.PI/180;CELLA=M.lat.map(l=>R*R*d*(Math.sin((l+0.5)*d)-Math.sin((l-0.5)*d)));}
  populateSelects();wireScenarioButtons();
  $("time").max=M.nt-1;$("hdr-range").textContent=`${M.times[0]}–${M.times[M.nt-1]}`;
  $("variable").onchange=()=>{setDefaultRange();refresh();replotSeries();};
  $("model").onchange=()=>{refresh();replotSeries();};
  $("mode").onchange=()=>{setDefaultRange();refresh();};
  $("proj").onchange=e=>{projName=e.target.value;$("map").style.cursor=projName==="orthographic"?"grab":"crosshair";setupMap();render();drawCoast();};
  $("cmap").onchange=()=>render();
  $("smooth").oninput=()=>render();
  $("deseason").onchange=$("detrend").onchange=()=>{drawGlobalMean();replotSeries();};
  $("time").oninput=e=>{T=+e.target.value;render();};
  $("vmin").onchange=$("vmax").onchange=()=>render();
  $("autorange").onclick=()=>{setDefaultRange();render();};
  $("pct").onclick=()=>{pctRange();render();};
  $("clearregion").onclick=()=>{region=null;regionPix=null;drawCoast();$("tsinfo").textContent="Click a cell, or drag a box on a flat map.";const[c,W,H]=fit($("ts"));c.clearRect(0,0,W,H);};
  $("play").onclick=togglePlay;$("speed").oninput=()=>{if(playing){stop();togglePlay();}};
  $("map").addEventListener("mousemove",onHover);$("map").addEventListener("mouseleave",()=>$("hover").textContent="");
  $("intercomp").addEventListener("mousemove",icHover);$("intercomp").addEventListener("mouseleave",()=>{const t=$("ictip");if(t)t.style.display="none";});
  setupPointer($("map"));
  window.addEventListener("resize",debounce(()=>{setupMap();render();drawCoast();drawIntercomp();drawRMSEBox();},200));
  $("rmsebox").addEventListener("mousemove",rmseHover);$("rmsebox").addEventListener("mouseleave",()=>{const t=$("rmsetip");if(t)t.style.display="none";});
  setDefaultRange();setupMap();setBoot("data…",65);await refresh();drawCoast();$("boot").classList.add("hide");
  requestAnimationFrame(()=>{drawIntercomp();drawGlobalMean();drawZonal();drawRMSEBox();});   // redraw panels once layout is final
}
function setBoot(m,p){$("boot-msg").textContent=m;$("boot-bar").style.width=p+"%";}
function debounce(fn,ms){let h;return(...a)=>{clearTimeout(h);h=setTimeout(()=>fn(...a),ms);};}

// ---- scenario handling (S2 / S3 / S3−S2 land-use difference) ----
const j=async u=>(await fetch(u)).json();
function diffGM(a,b){const out={};for(const v in a){out[v]={};for(const m in a[v]){const s3=a[v][m],s2=(b[v]||{})[m];if(!s2)continue;
  out[v][m]=s3.map((x,i)=>(x==null||s2[i]==null)?null:x-s2[i]);}}return out;}
async function loadScenarioData(scen){SCEN=scen;
  if(scen==="S3-S2"){const [m3,g3,g2]=await Promise.all([j("data/S3/manifest.json"),j("data/S3/globalmeans.json"),j("data/S2/globalmeans.json")]);
    M=m3;GM=diffGM(g3,g2);OBS={};RMSE=null;}
  else{M=await j(`data/${scen}/manifest.json`);GM=await j(`data/${scen}/globalmeans.json`);
    try{OBS=await j(`data/${scen}/obs.json`);}catch(e){OBS={};}
    try{RMSE=await j(`data/${scen}/rmse.json`);}catch(e){RMSE=null;}}
}
async function binFetch(scen,v,l){const ext=(M.binext||".bin");const raw=await(await fetch(`data/${scen}/${v}/${l}${ext}`)).arrayBuffer();
  // Pre-gzipped bins (static hosts can't set Content-Encoding reliably): detect gzip magic (1f 8b) and inflate; else use raw.
  const u=new Uint8Array(raw);let b=raw;
  if(u.length>1&&u[0]===0x1f&&u[1]===0x8b)b=await new Response(new Blob([raw]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
  return new Int16Array(b);}
function populateSelects(){const pv=$("variable").value,pm=$("model").value;
  $("variable").innerHTML="";$("model").innerHTML="";
  M.variables.forEach(v=>{const o=document.createElement("option");o.value=o.textContent=v.name;$("variable").appendChild(o);});
  M.models.forEach(m=>{const o=document.createElement("option");o.value=o.textContent=m;$("model").appendChild(o);});
  if([...$("variable").options].some(o=>o.value===pv))$("variable").value=pv;
  if([...$("model").options].some(o=>o.value===pm))$("model").value=pm;
  else $("model").value=M.models.find(m=>!m.startsWith("ENSEMBLE"))||M.models[0];}
function wireScenarioButtons(){document.querySelectorAll(".scenbtn").forEach(b=>b.onclick=()=>{
  if(b.classList.contains("active"))return;
  document.querySelectorAll(".scenbtn").forEach(x=>x.classList.remove("active"));b.classList.add("active");
  switchScenario(b.dataset.scen);});}
async function switchScenario(scen){$("status").textContent="loading "+scen+"…";
  for(const c of [cache,climCache,trendCache])for(const k in c)delete c[k];
  await loadScenarioData(scen);
  document.body.classList.toggle("scendiff",scen==="S3-S2");
  populateSelects();$("time").max=M.nt-1;if(T>M.nt-1)T=M.nt-1;$("time").value=T;
  setDefaultRange();await refresh();drawGlobalMean();drawIntercomp();drawRMSEBox();replotSeries();
  $("status").textContent=scen+" ✓";}
function isDiv(){return SCEN==="S3-S2"||curMode()==="anom"||curMode()==="diff"||curMode()==="trend"||vmeta(curVar()).diverging;}

function setDefaultRange(){const vm=vmeta(curVar()),m=curMode();let lo,hi;
  if(SCEN==="S3-S2"&&m!=="trend"){const a=+((vm.vmax-vm.vmin)*0.15).toFixed(3);hi=a;lo=-a;}
  else if(m==="value"){vm.diverging?(hi=vm.vmax,lo=-vm.vmax):(lo=vm.vmin,hi=vm.vmax);}
  else if(m==="trend"){const a=+((vm.vmax-vm.vmin)*0.15).toFixed(3);hi=a;lo=-a;}
  else{const a=+((vm.vmax-vm.vmin)*(m==="diff"?0.5:0.3)).toFixed(3);hi=a;lo=-a;}
  $("vmin").value=lo;$("vmax").value=hi;
  if(isDiv()&&!DIVERGING.has($("cmap").value))$("cmap").value="RdBu";
  if(!isDiv()&&DIVERGING.has($("cmap").value))$("cmap").value="viridis";
}
function pctRange(){const v=[];for(const x of disp)if(!isNaN(x))v.push(x);if(!v.length)return;v.sort((a,b)=>a-b);
  const lo=v[Math.floor(v.length*0.02)],hi=v[Math.floor(v.length*0.98)];
  if(isDiv()){const a=Math.max(Math.abs(lo),Math.abs(hi));$("vmin").value=(-a).toFixed(3);$("vmax").value=a.toFixed(3);}
  else{$("vmin").value=lo.toFixed(3);$("vmax").value=hi.toFixed(3);}}

async function fetchField(v,l){const kk=key(v,l);if(cache[kk])return cache[kk];
  $("status").textContent="loading "+v+"/"+l+"…";let out;
  if(SCEN==="S3-S2"){const [a3,a2]=await Promise.all([binFetch("S3",v,l),binFetch("S2",v,l)]);
    const F=M.fill;out=new Int16Array(a3.length);
    for(let i=0;i<out.length;i++){if(a3[i]===F||a2[i]===F){out[i]=F;continue;}const d=a3[i]-a2[i];out[i]=d>=32767?32767:d<=-32767?-32767:d;}}
  else{out=await binFetch(SCEN,v,l);}
  cache[kk]=out;$("status").textContent=v+"/"+l+" ✓";return out;}
const NC=()=>M.nlat*M.nlon,off=t=>t*NC();
function climatology(v,l,arr){const kk=key(v,l);if(climCache[kk])return climCache[kk];const nc=NC(),cl=new Float32Array(12*nc),cn=new Int32Array(12*nc);
  for(let t=0;t<M.nt;t++){const cm=t%12,o=off(t);for(let c=0;c<nc;c++){const r=arr[o+c];if(r!==M.fill){cl[cm*nc+c]+=r;cn[cm*nc+c]++;}}}
  for(let i=0;i<cl.length;i++)cl[i]=cn[i]?cl[i]/cn[i]:NaN;climCache[kk]=cl;return cl;}
function trendMap(v,l,arr,scale){const kk=key(v,l);if(trendCache[kk])return trendCache[kk];const nc=NC(),out=new Float32Array(nc);
  const perDec=M.cadence==="annual"?10:120,minN=M.cadence==="annual"?10:24;  // per-decade steps + min length, cadence-aware (annual store → short-record models like CARDAMOM 2003- now get a trend)
  for(let c=0;c<nc;c++){let n=0,sx=0,sy=0,sxx=0,sxy=0;for(let t=0;t<M.nt;t++){const r=arr[off(t)+c];if(r===M.fill)continue;const y=r*scale;n++;sx+=t;sy+=y;sxx+=t*t;sxy+=t*y;}
    if(n>=minN){const d=n*sxx-sx*sx;out[c]=d?((n*sxy-sx*sy)/d)*perDec:NaN;}else out[c]=NaN;}  // slope per decade
  trendCache[kk]=out;return out;}

async function refresh(){const v=curVar(),l=curLayer(),mode=curMode(),scale=vmeta(v).scale;
  const arr=await fetchField(v,l);const ens=mode==="diff"?await fetchField(v,"ENSEMBLE-mean"):null;
  const cl=mode==="anom"?climatology(v,l,arr):null;const tr=mode==="trend"?trendMap(v,l,arr,scale):null;
  refresh._c={v,l,mode,arr,ens,cl,tr,scale};
  $("gmunits").textContent="("+gmUnits(v)+", "+(gmKind(v)==="mean"?"area-mean":"global total")+")";render();drawIntercomp();
}
function buildFrame(){const {arr,ens,cl,tr,scale}=refresh._c,mode=curMode(),nc=NC(),o=off(T),f=new Float32Array(nc);
  if(mode==="trend"){for(let c=0;c<nc;c++)f[c]=tr[c];return f;}
  for(let c=0;c<nc;c++){const r=arr[o+c];if(r===M.fill){f[c]=NaN;continue;}
    if(mode==="value")f[c]=r*scale;else if(mode==="anom"){const cm=cl[(T%12)*nc+c];f[c]=isNaN(cm)?NaN:(r-cm)*scale;}
    else{const e=ens[o+c];f[c]=e===M.fill?NaN:(r-e)*scale;}}return f;}
function boxblur(f){const nlon=M.nlon,nlat=M.nlat,g=new Float32Array(f.length);
  for(let j=0;j<nlat;j++)for(let i=0;i<nlon;i++){let s=0,n=0;for(let dj=-1;dj<=1;dj++){const jj=j+dj;if(jj<0||jj>=nlat)continue;for(let di=-1;di<=1;di++){const ii=(i+di+nlon)%nlon,v=f[jj*nlon+ii];if(!isNaN(v)){s+=v;n++;}}}g[j*nlon+i]=n?s/n:NaN;}return g;}
function sample(f,gx,gy,bilinear){const nlon=M.nlon,nlat=M.nlat;
  if(!bilinear)return f[Math.round(gy)*nlon+Math.round(gx)];
  const i0=Math.floor(gx),j0=Math.floor(gy),fx=gx-i0,fy=gy-j0,i1=(i0+1)%nlon,j1=Math.min(j0+1,nlat-1);
  const a=f[j0*nlon+i0],b=f[j0*nlon+i1],c=f[j1*nlon+i0],d=f[j1*nlon+i1];
  if(isNaN(a)||isNaN(b)||isNaN(c)||isNaN(d))return f[Math.round(gy)*nlon+Math.round(gx)];
  return a*(1-fx)*(1-fy)+b*fx*(1-fy)+c*(1-fx)*fy+d*fx*fy;}

function render(){if(!refresh._c)return;let frame=buildFrame();disp=frame;
  const sm=+$("smooth").value;let sf=frame;for(let p=1;p<sm;p++)sf=boxblur(sf);       // extra blur passes
  const W=MW,H=MH,lo=+$("vmin").value,hi=+$("vmax").value,anc=CMAPS[$("cmap").value],bilinear=sm>=1;
  OFF.width=W;OFF.height=H;const octx=OFF.getContext("2d"),img=octx.createImageData(W,H),D=img.data;
  for(let p=0;p<W*H;p++){const gx=PX[p];if(isNaN(gx)){D[p*4+3]=0;continue;}const val=sample(sf,gx,PY[p],bilinear);const q=p*4;
    if(isNaN(val)){D[q+3]=0;continue;}const col=lutColor(anc,(val-lo)/(hi-lo));D[q]=col[0];D[q+1]=col[1];D[q+2]=col[2];D[q+3]=255;}
  octx.putImageData(img,0,0);
  const ctx=$("map").getContext("2d");ctx.clearRect(0,0,W,H);ctx.fillStyle="#0d1a24";ctx.fill(window._sphere);
  ctx.save();ctx.clip(window._land);ctx.drawImage(OFF,0,0);ctx.restore();
  $("tlabel").textContent=M.times[T];$("kpi-month").textContent=M.times[T];
  drawColorbar();updateKPIs();drawZonal();drawGlobalMean();
}
function updateKPIs(){const {arr,scale}=refresh._c,v=curVar(),kind=gmKind(v),nc=NC(),o=off(T);
  let acc=0,wsum=0,valid=0;
  for(let j=0;j<M.nlat;j++){const a=CELLA[j];for(let i=0;i<M.nlon;i++){const r=arr[o+j*M.nlon+i];if(r===M.fill)continue;const val=r*scale;valid++;
    if(kind==="flux")acc+=val*a*365*1e-15;else if(kind==="pool")acc+=val*a*1e-12;else{acc+=val*a;wsum+=a;}}}
  const out=kind==="mean"?(wsum?acc/wsum:NaN):acc;
  $("kpi-mean").textContent=isNaN(out)?"–":fmt(out);
  $("kpi-mean").parentElement.querySelector(".kpi-k").textContent=(kind==="mean"?"global mean · ":"global total · ")+gmUnits(v);
  $("kpi-valid").textContent=valid.toLocaleString()+" ("+(100*valid/nc).toFixed(0)+"%)";}

function setupMap(){const wrap=$("mapwrap");DPR=Math.min(window.devicePixelRatio||1,2);
  const W=Math.min((wrap.clientWidth*DPR)|0,2000),H=(W/2)|0;MW=W;MH=H;
  for(const id of["map","coast"]){const c=$(id);c.width=W;c.height=H;}
  const proj=PROJS[projName]().fitExtent([[6,6],[W-6,H-6]],{type:"Sphere"});window._proj=proj;
  const gp=d3.geoPath(proj);window._sphere=new Path2D(gp({type:"Sphere"}));window._land=new Path2D(gp(LAND));
  PX=new Float32Array(W*H);PY=new Float32Array(W*H);const nlon=M.nlon,nlat=M.nlat;
  for(let py=0;py<H;py++)for(let px=0;px<W;px++){const sx=px+.5,sy=py+.5,idx=py*W+px,g=proj.invert([sx,sy]);
    if(!g||isNaN(g[0])||isNaN(g[1])){PX[idx]=NaN;continue;}const fw=proj(g);
    if(!fw||Math.abs(fw[0]-sx)>.75||Math.abs(fw[1]-sy)>.75){PX[idx]=NaN;continue;}
    let gx=g[0]+179.5;if(gx<0)gx+=360;if(gx>nlon-1)gx-=nlon;PX[idx]=Math.max(0,Math.min(nlon-1,gx));PY[idx]=Math.max(0,Math.min(nlat-1,g[1]+89.5));}}
function drawCoast(){const c=$("coast"),ctx=c.getContext("2d"),proj=window._proj;ctx.clearRect(0,0,MW,MH);const path=d3.geoPath(proj,ctx);
  ctx.beginPath();path({type:"Sphere"});ctx.strokeStyle="rgba(120,150,170,.5)";ctx.lineWidth=1*DPR;ctx.stroke();
  ctx.beginPath();path(d3.geoGraticule10());ctx.strokeStyle="rgba(255,255,255,.06)";ctx.lineWidth=.5*DPR;ctx.stroke();
  ctx.beginPath();path(LAND);ctx.strokeStyle="rgba(210,225,235,.5)";ctx.lineWidth=.7*DPR;ctx.stroke();
  if(regionPix){ctx.strokeStyle="#5ed0c5";ctx.lineWidth=1.5*DPR;ctx.setLineDash([5*DPR,3*DPR]);ctx.strokeRect(regionPix.x0,regionPix.y0,regionPix.x1-regionPix.x0,regionPix.y1-regionPix.y0);ctx.setLineDash([]);}}

function stop(){clearInterval(playing);playing=null;$("play").textContent="▶";}
function togglePlay(){if(playing){stop();return;}$("play").textContent="⏸";playing=setInterval(()=>{T=(T+1)%M.nt;$("time").value=T;render();},1000/(+$("speed").value));}

// ---- pointer: rotate globe (orthographic) or region brush (flat) ----
function setupPointer(map){let mode=null,start=null;
  map.addEventListener("pointerdown",e=>{map.setPointerCapture(e.pointerId);const r=map.getBoundingClientRect();
    start={x:e.clientX,y:e.clientY,px:(e.clientX-r.left)/r.width*MW,py:(e.clientY-r.top)/r.height*MH,rot:rot.slice()};
    mode=projName==="orthographic"?"rot":"box";if(mode==="rot")map.style.cursor="grabbing";});
  map.addEventListener("pointermove",e=>{if(!mode)return;const r=map.getBoundingClientRect();
    if(mode==="rot"){const k=.4;rot=[start.rot[0]+(e.clientX-start.x)*k,Math.max(-90,Math.min(90,start.rot[1]-(e.clientY-start.y)*k))];scheduleGlobe();}
    else{const px=(e.clientX-r.left)/r.width*MW,py=(e.clientY-r.top)/r.height*MH;regionPix={x0:Math.min(start.px,px),y0:Math.min(start.py,py),x1:Math.max(start.px,px),y1:Math.max(start.py,py)};drawCoast();}});
  const end=()=>{if(mode==="rot")map.style.cursor="grab";if(mode==="box"&&regionPix)finalizeRegion();mode=null;};
  map.addEventListener("pointerup",end);map.addEventListener("pointercancel",end);}
function finalizeRegion(){ // pixel box -> grid bounds
  let i0=1e9,i1=-1,j0=1e9,j1=-1;
  for(let py=Math.floor(regionPix.y0);py<=Math.ceil(regionPix.y1);py++)for(let px=Math.floor(regionPix.x0);px<=Math.ceil(regionPix.x1);px++){
    if(px<0||px>=MW||py<0||py>=MH)continue;const gx=PX[py*MW+px];if(isNaN(gx))continue;const i=Math.round(gx),j=Math.round(PY[py*MW+px]);
    if(i<i0)i0=i;if(i>i1)i1=i;if(j<j0)j0=j;if(j>j1)j1=j;}
  if(i1<0){region=null;return;}region={i0,i1,j0,j1};replotSeries();}

function onHover(e){const r=$("map").getBoundingClientRect();const px=(e.clientX-r.left)/r.width*MW|0,py=(e.clientY-r.top)/r.height*MH|0;
  if(px<0||px>=MW||py<0||py>=MH||!disp){$("hover").textContent="";return;}const gx=PX[py*MW+px];if(isNaN(gx)){$("hover").textContent="";return;}
  const i=Math.round(gx),j=Math.round(PY[py*MW+px]),v=disp[j*M.nlon+i];
  $("hover").textContent=`${M.lat[j].toFixed(1)}°, ${M.lon[i].toFixed(1)}°  ${isNaN(v)?"—":v.toFixed(2)}`;}

// ---- series (cell click uses region of 1 cell) ----
$("map")&&$("map").addEventListener("click",e=>{ if($("proj").value!=="orthographic"){ if(regionPix)return; } // box handled on pointerup
  const r=$("map").getBoundingClientRect();const px=(e.clientX-r.left)/r.width*MW|0,py=(e.clientY-r.top)/r.height*MH|0;
  const gx=PX[py*MW+px];if(isNaN(gx))return;const i=Math.round(gx),j=Math.round(PY[py*MW+px]);region={i0:i,i1:i,j0:j,j1:j};regionPix=null;drawCoast();replotSeries();});

function regionSeries(){if(!region)return null;const {arr,scale}=refresh._c;const s=new Float32Array(M.nt);let any=false;
  for(let t=0;t<M.nt;t++){let num=0,den=0;for(let j=region.j0;j<=region.j1;j++){const w=COSLAT[j];for(let i=region.i0;i<=region.i1;i++){const rr=arr[off(t)+j*M.nlon+i];if(rr!==M.fill){num+=rr*scale*w;den+=w;}}}s[t]=den?num/den:NaN;if(den)any=true;}
  return any?s:null;}
function transform(s){let r=s.slice();
  if($("deseason").checked){const nc=12,sum=new Float64Array(nc),cnt=new Int32Array(nc);for(let t=0;t<r.length;t++)if(!isNaN(r[t])){sum[t%12]+=r[t];cnt[t%12]++;}
    const clim=sum.map((x,i)=>cnt[i]?x/cnt[i]:0);for(let t=0;t<r.length;t++)if(!isNaN(r[t]))r[t]-=clim[t%12];}
  if($("detrend").checked){const f=linfit(r);if(f)for(let t=0;t<r.length;t++)if(!isNaN(r[t]))r[t]-=f.a+f.b*t;}
  return r;}
function linfit(s){let n=0,sx=0,sy=0,sxx=0,sxy=0;for(let t=0;t<s.length;t++){if(isNaN(s[t]))continue;n++;sx+=t;sy+=s[t];sxx+=t*t;sxy+=t*s[t];}
  if(n<3)return null;const d=n*sxx-sx*sx;if(!d)return null;const b=(n*sxy-sx*sy)/d,a=(sy-b*sx)/n;return{a,b};}
function replotSeries(){if(!region||!refresh._c)return;const s0=regionSeries();if(!s0){$("tsinfo").textContent="No land data in selection.";return;}
  const s=transform(s0);const f=linfit(s);const v=curVar(),u=vmeta(v).units;
  const lbl=(region.i0===region.i1&&region.j0===region.j1)?`cell ${M.lat[region.j0].toFixed(1)}°,${M.lon[region.i0].toFixed(1)}°`:`region ${M.lat[region.j0].toFixed(0)}–${M.lat[region.j1].toFixed(0)}°N, ${M.lon[region.i0].toFixed(0)}–${M.lon[region.i1].toFixed(0)}°E`;
  $("tstitle").textContent=lbl;
  const slope=f?(f.b*(M.cadence==="annual"?10:120)):NaN; // per decade (cadence-aware)
  $("tsinfo").textContent=`${curLayer()} · ${v} (${u})`+(isNaN(slope)?"":` · trend ${slope>=0?"+":""}${slope.toPrecision(2)} /decade`)+($("deseason").checked?" · deseasonalized":"")+($("detrend").checked?" · detrended":"");
  linePlot($("ts"),s,"#4cc38a",f);}

function drawColorbar(){const cv=$("cbar2"),a=CMAPS[$("cmap").value];const dpr=Math.min(window.devicePixelRatio||1,2);
  const W=cv.clientWidth||480,H=70;cv.width=Math.round(W*dpr);cv.height=Math.round(H*dpr);const ctx=cv.getContext("2d");ctx.setTransform(dpr,0,0,dpr,0,0);
  const bw=W,bh=20;for(let i=0;i<bw;i++){const c=lutColor(a,i/(bw-1));ctx.fillStyle=`rgb(${c[0]|0},${c[1]|0},${c[2]|0})`;ctx.fillRect(i,0,1,bh);}
  const v=curVar(),u=vmeta(v).units,m=curMode(),lo=+$("vmin").value,hi=+$("vmax").value;
  const title=`${vlabel(v)} (${u})`+(m==="anom"?" — anomaly":m==="diff"?" — Δ ensemble":m==="trend"?" — trend /decade":"");
  ctx.textBaseline="alphabetic";ctx.font="600 14px system-ui";ctx.fillStyle="#e6edf3";ctx.textAlign="left";ctx.fillText(fmt(lo),0,bh+18);
  ctx.textAlign="right";ctx.fillText(fmt(hi),bw,bh+18);ctx.textAlign="center";ctx.fillStyle="#e6edf3";ctx.font="700 14px system-ui";ctx.fillText(title,bw/2,bh+42);}
function fmt(x){return Math.abs(x)>=100?x.toFixed(0):Math.abs(x)>=1?(+x).toFixed(1):(+x).toFixed(3);}

function fit(cv){const dpr=Math.min(window.devicePixelRatio||1,2);const W=cv.clientWidth||480,H=cv.clientHeight||150;
  cv.width=Math.round(W*dpr);cv.height=Math.round(H*dpr);const ctx=cv.getContext("2d");ctx.setTransform(dpr,0,0,dpr,0,0);return[ctx,W,H];}
function niceTicks(lo,hi,n){n=n||4;const sp=(hi-lo)||1,s0=sp/n,mag=Math.pow(10,Math.floor(Math.log10(s0))),nm=s0/mag,step=(nm<1.5?1:nm<3?2:nm<7?5:10)*mag,st=Math.ceil(lo/step)*step,t=[];for(let x=st;x<=hi+step*1e-6;x+=step)t.push(x);return t;}
function fmtv(x){const a=Math.abs(x);return a===0?"0":a>=100?x.toFixed(0):a>=10?x.toFixed(0):a>=1?x.toFixed(1):a>=0.01?x.toFixed(2):x.toExponential(0);}
function yaxis(ctx,W,H,pad,ymn,ymx,title,units){
  ctx.strokeStyle="#2a333d";ctx.beginPath();ctx.moveTo(pad.l,pad.t);ctx.lineTo(pad.l,H-pad.b);ctx.lineTo(W-pad.r,H-pad.b);ctx.stroke();ctx.font="11px system-ui";
  for(const tv of niceTicks(ymn,ymx,4)){if(tv<ymn-1e-9||tv>ymx+1e-9)continue;const y=H-pad.b-(tv-ymn)/(ymx-ymn)*(H-pad.t-pad.b);
    ctx.strokeStyle="rgba(255,255,255,.05)";ctx.beginPath();ctx.moveTo(pad.l,y);ctx.lineTo(W-pad.r,y);ctx.stroke();ctx.fillStyle="#76828f";ctx.textAlign="right";ctx.fillText(fmtv(tv),pad.l-4,y+3);}
  if(units){ctx.save();ctx.translate(10,(pad.t+H-pad.b)/2);ctx.rotate(-Math.PI/2);ctx.textAlign="center";ctx.fillStyle="#8b98a5";ctx.font="11px system-ui";ctx.fillText(units,0,0);ctx.restore();}
  if(title){ctx.textAlign="left";ctx.fillStyle="#e6edf3";ctx.font="700 13px system-ui";ctx.fillText(title,pad.l+4,pad.t+11);}
}
function xyears(ctx,W,H,pad,n,X){ctx.fillStyle="#8b98a5";ctx.font="11px system-ui";ctx.textAlign="center";for(let t=0;t<n;t+=120)ctx.fillText(M.times[t].slice(0,4),X(t),H-5);}
function linePlot(cv,s,color,f){const [ctx,W,H]=fit(cv);ctx.clearRect(0,0,W,H);const pad={l:50,r:10,t:20,b:22};
  let mn=Infinity,mx=-Infinity;for(const v of s)if(!isNaN(v)){mn=Math.min(mn,v);mx=Math.max(mx,v);}if(!isFinite(mn))return;if(mn===mx){mn-=1;mx+=1;}
  const X=t=>pad.l+t/(s.length-1)*(W-pad.l-pad.r),Y=v=>H-pad.b-(v-mn)/(mx-mn)*(H-pad.t-pad.b);
  yaxis(ctx,W,H,pad,mn,mx,vlabel(curVar()),vmeta(curVar()).units);xyears(ctx,W,H,pad,s.length,X);
  if(f){ctx.strokeStyle="rgba(227,160,8,.9)";ctx.setLineDash([5,3]);ctx.beginPath();ctx.moveTo(X(0),Y(f.a));ctx.lineTo(X(s.length-1),Y(f.a+f.b*(s.length-1)));ctx.stroke();ctx.setLineDash([]);}
  ctx.strokeStyle=color;ctx.lineWidth=1.2;ctx.beginPath();let st=false;for(let t=0;t<s.length;t++){if(isNaN(s[t])){st=false;continue;}const x=X(t),y=Y(s[t]);st?ctx.lineTo(x,y):(ctx.moveTo(x,y),st=true);}ctx.stroke();}
function drawGlobalMean(){const v=curVar(),sel=curLayer(),[ctx,W,H]=fit($("gm"));ctx.clearRect(0,0,W,H);const pad={l:50,r:10,t:20,b:22};
  const S=GM[v];if(!S)return;const tf=k=>transform(Float32Array.from(S[k].map(x=>x==null?NaN:x)));
  const T2={};for(const k in S)T2[k]=tf(k);let mn=Infinity,mx=-Infinity;for(const k in T2)for(const x of T2[k])if(!isNaN(x)){mn=Math.min(mn,x);mx=Math.max(mx,x);}if(!isFinite(mn))return;if(mn===mx){mn-=1;mx+=1;}
  const n=M.nt,X=t=>pad.l+t/(n-1)*(W-pad.l-pad.r),Y=x=>H-pad.b-(x-mn)/(mx-mn)*(H-pad.t-pad.b);
  yaxis(ctx,W,H,pad,mn,mx,vlabel(v),gmUnits(v));xyears(ctx,W,H,pad,n,X);
  const dr=(k,col,w)=>{const s=T2[k];if(!s)return;ctx.strokeStyle=col;ctx.lineWidth=w;ctx.beginPath();let st=false;for(let t=0;t<n;t++){if(isNaN(s[t])){st=false;continue;}const x=X(t),y=Y(s[t]);st?ctx.lineTo(x,y):(ctx.moveTo(x,y),st=true);}ctx.stroke();};
  for(const k in T2){if(k.startsWith("ENSEMBLE")||k===sel)continue;dr(k,"rgba(118,130,143,.22)",.5);}dr("ENSEMBLE-mean","#e3a008",1.4);if(!sel.startsWith("ENSEMBLE"))dr(sel,"#4cc38a",1.5);
  ctx.strokeStyle="rgba(230,237,243,.4)";ctx.beginPath();ctx.moveTo(X(T),pad.t);ctx.lineTo(X(T),H-pad.b);ctx.stroke();}
function drawZonal(){const [ctx,W,H]=fit($("zonal"));ctx.clearRect(0,0,W,H);const pad={l:40,r:12,t:12,b:34};const nlon=M.nlon,nlat=M.nlat,zm=new Float64Array(nlat);
  for(let j=0;j<nlat;j++){let s=0,c=0;for(let i=0;i<nlon;i++){const v=disp[j*nlon+i];if(!isNaN(v)){s+=v;c++;}}zm[j]=c?s/c:NaN;}
  let mn=Infinity,mx=-Infinity;for(const v of zm)if(!isNaN(v)){mn=Math.min(mn,v);mx=Math.max(mx,v);}if(!isFinite(mn))return;if(mn===mx){mn-=1;mx+=1;}
  const Y=j=>pad.t+(nlat-1-j)/(nlat-1)*(H-pad.t-pad.b),X=v=>pad.l+(v-mn)/(mx-mn)*(W-pad.l-pad.r);
  ctx.strokeStyle="#2a333d";ctx.beginPath();ctx.moveTo(pad.l,pad.t);ctx.lineTo(pad.l,H-pad.b);ctx.lineTo(W-pad.r,H-pad.b);ctx.stroke();
  ctx.font="11px system-ui";ctx.fillStyle="#8b98a5";ctx.textAlign="right";
  for(const [lab,latv] of [["90N",89],["60N",60],["30N",30],["0",0],["30S",-30],["60S",-60],["90S",-89]]){const y=Y(latv+89.5);ctx.fillText(lab,pad.l-4,y+4);}
  ctx.textAlign="center";for(const tv of niceTicks(mn,mx,3)){if(tv<mn||tv>mx)continue;const x=X(tv);ctx.strokeStyle="rgba(255,255,255,.05)";ctx.beginPath();ctx.moveTo(x,pad.t);ctx.lineTo(x,H-pad.b);ctx.stroke();ctx.fillStyle="#76828f";ctx.fillText(fmtv(tv),x,H-19);}
  ctx.fillStyle="#c7d2dc";ctx.font="600 12px system-ui";ctx.fillText(vaxis(curVar()),(pad.l+W-pad.r)/2,H-5);
  if(isDiv()){const x0=X(Math.max(mn,Math.min(mx,0)));ctx.strokeStyle="#345";ctx.beginPath();ctx.moveTo(x0,pad.t);ctx.lineTo(x0,H-pad.b);ctx.stroke();}
  ctx.strokeStyle="#7aa2f7";ctx.lineWidth=1.4;ctx.beginPath();let st=false;for(let j=0;j<nlat;j++){if(isNaN(zm[j])){st=false;continue;}const x=X(zm[j]),y=Y(j);st?ctx.lineTo(x,y):(ctx.moveTo(x,y),st=true);}ctx.stroke();}

function annualStats(arr){
  const yrs=[];for(let y=0;y<Math.floor(arr.length/12);y++){let s=0,n=0;for(let mm=0;mm<12;mm++){const x=arr[y*12+mm];if(x!=null&&!isNaN(x)){s+=x;n++;}}if(n)yrs.push(s/n);}
  if(!yrs.length)return null;const m=yrs.reduce((a,b)=>a+b,0)/yrs.length;const vv=yrs.reduce((a,b)=>a+(b-m)*(b-m),0)/yrs.length;return{mean:m,std:Math.sqrt(vv)};}
function drawIntercomp(){
  const v=curVar(),S=GM[v];if(!S)return;const [ctx,W,H]=fit($("intercomp"));ctx.clearRect(0,0,W,H);
  $("icunits").textContent="("+gmUnits(v)+")";
  let models=[];for(const k in S){if(k.startsWith("ENSEMBLE"))continue;const st=annualStats(S[k]);if(st)models.push({name:k,mean:st.mean,std:st.std,type:"model"});}
  if(!models.length)return;models.sort((a,b)=>b.mean-a.mean);
  const ensMean=models.reduce((a,b)=>a+b.mean,0)/models.length;
  const ensStd=Math.sqrt(models.reduce((a,b)=>a+(b.mean-ensMean)**2,0)/models.length);
  const items=[...models,{name:"Ensemble",mean:ensMean,std:ensStd,type:"ens"}];
  (OBS[v]||[]).forEach(o=>items.push({name:o.name,mean:o.value,std:o.std,type:"obs"}));
  const pad={l:72,r:12,t:14,b:104};
  let ymax=0;for(const it of items)ymax=Math.max(ymax,it.mean+(it.std||0));ymax*=1.08;if(ymax<=0)ymax=1;
  const n=items.length,bw=(W-pad.l-pad.r)/n,bar=bw*0.7;
  const X=i=>pad.l+i*bw+bw/2,Y=y=>H-pad.b-(y/ymax)*(H-pad.t-pad.b);
  ctx.strokeStyle="#233";ctx.fillStyle="#8b98a5";ctx.font="12px system-ui";
  ctx.beginPath();ctx.moveTo(pad.l,pad.t);ctx.lineTo(pad.l,H-pad.b);ctx.lineTo(W-pad.r,H-pad.b);ctx.stroke();
  ctx.textAlign="right";for(let g=0;g<=4;g++){const yv=ymax*g/4,y=Y(yv);ctx.fillText(yv.toFixed(yv<10?1:0),pad.l-6,y+4);ctx.strokeStyle="rgba(255,255,255,.05)";ctx.beginPath();ctx.moveTo(pad.l,y);ctx.lineTo(W-pad.r,y);ctx.stroke();}
  ctx.save();ctx.translate(17,(pad.t+H-pad.b)/2);ctx.rotate(-Math.PI/2);ctx.textAlign="center";ctx.fillStyle="#c7d2dc";ctx.font="600 14px system-ui";ctx.fillText(vlabel(v)+"  ("+gmUnits(v)+")",0,0);ctx.restore();
  const dx=pad.l+models.length*bw;ctx.strokeStyle="rgba(255,255,255,.35)";ctx.setLineDash([4,3]);ctx.beginPath();ctx.moveTo(dx,pad.t);ctx.lineTo(dx,H-pad.b);ctx.stroke();ctx.setLineDash([]);
  const col={model:"#6cb2e0",ens:"#e3a008",obs:"#4cc38a"};
  items.forEach((it,i)=>{const x=X(i),y0=H-pad.b,y1=Y(it.mean);
    ctx.fillStyle=col[it.type];ctx.fillRect(x-bar/2,y1,bar,y0-y1);
    ctx.strokeStyle="#0b0f14";ctx.lineWidth=1;ctx.strokeRect(x-bar/2,y1,bar,y0-y1);
    if(it.std){const yl=Y(it.mean-it.std),yh=Y(it.mean+it.std);ctx.strokeStyle="#e6edf3";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x,yl);ctx.lineTo(x,yh);ctx.moveTo(x-3,yl);ctx.lineTo(x+3,yl);ctx.moveTo(x-3,yh);ctx.lineTo(x+3,yh);ctx.stroke();}
    ctx.save();ctx.translate(x+4,H-pad.b+9);ctx.rotate(-Math.PI/4);ctx.textAlign="right";ctx.fillStyle=it.type==="model"?"#c2ccd6":"#eef3f8";ctx.font=(it.type==="model"?"12px ":"700 12px ")+"system-ui";ctx.fillText(it.name,0,0);ctx.restore();});
  const on=(OBS[v]||[]).map(o=>o.name).join(", ");
  if($("iccap"))$("iccap").textContent="models (blue, high→low) · ensemble ±1σ across models (orange) · obs (green): "+(on||"—");
  IC={items,pad,bw,bar,W,H,v};               // stash geometry for hover tooltip
}
function icHover(e){const cv=$("intercomp"),tip=$("ictip");if(!IC||!tip)return;
  const r=cv.getBoundingClientRect(),mx=(e.clientX-r.left)*cv.clientWidth/r.width,my=(e.clientY-r.top)*cv.clientHeight/r.height;
  const {items,pad,bw,W,H,v}=IC,i=Math.floor((mx-pad.l)/bw);
  if(mx<pad.l||mx>W-pad.r||my<pad.t||my>H-pad.b||i<0||i>=items.length){tip.style.display="none";return;}
  const it=items[i],f=x=>Math.abs(x)>=100?x.toFixed(1):x.toFixed(2),u=gmUnits(v);
  const kind=it.type==="obs"?" (obs)":it.type==="ens"?" (ensemble)":"";
  tip.innerHTML=`<b>${it.name}</b>${kind}<br>${f(it.mean)}${it.std?" ± "+f(it.std):""} ${u}`;
  tip.style.display="block";
  const px=(e.clientX-r.left)+cv.offsetLeft,py=(e.clientY-r.top)+cv.offsetTop;
  tip.style.left=Math.min(px+12,cv.offsetLeft+cv.clientWidth-tip.offsetWidth-4)+"px";
  tip.style.top=Math.max(py-tip.offsetHeight-8,cv.offsetTop+2)+"px";
}
function quart(a){a=a.slice().sort((x,y)=>x-y);const q=p=>{const i=(a.length-1)*p,lo=Math.floor(i),hi=Math.ceil(i);return a[lo]+(a[hi]-a[lo])*(i-lo);};
  return{min:a[0],q1:q(.25),med:q(.5),q3:q(.75),max:a[a.length-1]};}
// stable pseudo-random offset in (-1,1) from a string (so dots scatter, not line up)
function hjit(s){let h=2166136261;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619);}return ((h>>>0)/4294967295)*2-1;}
let RMSEHIT=null;
function drawRMSEBox(){
  const cv=$("rmsebox");if(!cv||!RMSE||!RMSE.vars)return;const [ctx,W,H]=fit(cv);ctx.clearRect(0,0,W,H);
  const pad={l:56,r:14,t:14,b:48},groups=RMSE.vars;
  let mx=0;for(const g of groups)for(const d of g.models)mx=Math.max(mx,d.r);mx*=1.1;if(mx<=0)mx=1;
  const Y=v=>H-pad.b-(v/mx)*(H-pad.t-pad.b);
  ctx.strokeStyle="#2a333d";ctx.beginPath();ctx.moveTo(pad.l,pad.t);ctx.lineTo(pad.l,H-pad.b);ctx.lineTo(W-pad.r,H-pad.b);ctx.stroke();
  ctx.font="11px system-ui";for(const tv of niceTicks(0,mx,4)){const y=Y(tv);ctx.strokeStyle="rgba(255,255,255,.05)";ctx.beginPath();ctx.moveTo(pad.l,y);ctx.lineTo(W-pad.r,y);ctx.stroke();ctx.fillStyle="#8b98a5";ctx.textAlign="right";ctx.fillText(fmtv(tv),pad.l-5,y+4);}
  ctx.save();ctx.translate(12,(pad.t+H-pad.b)/2);ctx.rotate(-Math.PI/2);ctx.textAlign="center";ctx.fillStyle="#c7d2dc";ctx.font="600 13px system-ui";ctx.fillText("RMSE ("+RMSE.units+")",0,0);ctx.restore();
  const gw=(W-pad.l-pad.r)/groups.length,hits=[];
  groups.forEach((g,gi)=>{const cx=pad.l+(gi+0.5)*gw,bw=Math.min(64,gw*0.5);
    const s=quart(g.models.map(d=>d.r));
    ctx.strokeStyle="#5b6b7a";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(cx,Y(s.min));ctx.lineTo(cx,Y(s.max));
    ctx.moveTo(cx-bw*0.25,Y(s.min));ctx.lineTo(cx+bw*0.25,Y(s.min));ctx.moveTo(cx-bw*0.25,Y(s.max));ctx.lineTo(cx+bw*0.25,Y(s.max));ctx.stroke();
    ctx.fillStyle="rgba(108,178,224,.12)";ctx.strokeStyle="#6cb2e0";ctx.lineWidth=1.2;const yq3=Y(s.q3);ctx.fillRect(cx-bw/2,yq3,bw,Y(s.q1)-yq3);ctx.strokeRect(cx-bw/2,yq3,bw,Y(s.q1)-yq3);
    ctx.strokeStyle="#e3a008";ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(cx-bw/2,Y(s.med));ctx.lineTo(cx+bw/2,Y(s.med));ctx.stroke();
    g.models.forEach(d=>{const jx=cx+hjit(g.key+d.m)*bw*0.42,y=Y(d.r),ens=d.m==="TRENDY-ENSEMBLE";
      ctx.beginPath();ctx.arc(jx,y,ens?6:3.6,0,7);ctx.fillStyle=ens?"#e3a008":"rgba(150,205,235,.78)";ctx.fill();
      ctx.strokeStyle=ens?"#fff":"rgba(11,15,20,.8)";ctx.lineWidth=ens?1.6:1;ctx.stroke();
      hits.push({x:jx,y,m:d.m,r:d.r});});
    ctx.fillStyle="#e6edf3";ctx.font="700 14px system-ui";ctx.textAlign="center";ctx.fillText(g.label,cx,H-pad.b+20);
    ctx.fillStyle="#76828f";ctx.font="11px system-ui";ctx.fillText("vs "+g.source,cx,H-pad.b+36);});
  RMSEHIT={hits,units:RMSE.units};
}
function rmseHover(e){const cv=$("rmsebox"),tip=$("rmsetip");if(!RMSEHIT||!tip)return;
  const r=cv.getBoundingClientRect(),mx=(e.clientX-r.left)*cv.clientWidth/r.width,my=(e.clientY-r.top)*cv.clientHeight/r.height;
  let best=null,bd=100;for(const h of RMSEHIT.hits){const dx=h.x-mx,dy=h.y-my,dd=dx*dx+dy*dy;if(dd<bd){bd=dd;best=h;}}
  if(!best){tip.style.display="none";return;}
  const nm=best.m==="TRENDY-ENSEMBLE"?"TRENDY-ENSEMBLE (ensemble)":best.m;
  tip.innerHTML=`<b>${nm}</b><br>RMSE ${best.r.toFixed(3)} ${RMSEHIT.units}`;tip.style.display="block";
  const px=(e.clientX-r.left)+cv.offsetLeft,py=(e.clientY-r.top)+cv.offsetTop;
  tip.style.left=Math.min(px+12,cv.offsetLeft+cv.clientWidth-tip.offsetWidth-4)+"px";
  tip.style.top=Math.max(py-tip.offsetHeight-8,cv.offsetTop+2)+"px";
}

boot();
