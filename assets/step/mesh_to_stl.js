/* App-owned adapter. OCCT converts STEP coordinates to millimetres first. */
(function(root){
'use strict';
function stepMeshToStl(result){
  if(!result||result.success!==true||!Array.isArray(result.meshes)||!result.meshes.length)throw Error('STEP_EMPTY');
  let count=0;
  for(const mesh of result.meshes){
    const p=mesh.attributes?.position?.array,ix=mesh.index?.array;
    if(!Array.isArray(p)||!Array.isArray(ix)||p.length%3||ix.length%3)throw Error('STEP_MESH');
    count+=ix.length/3;
    if(count>500000)throw Error('STEP_COMPLEX');
    if(p.some(v=>!Number.isFinite(v)||Math.abs(v)>1e7))throw Error('STEP_COORDINATES');
    if(ix.some(i=>!Number.isSafeInteger(i)||i<0||i*3+2>=p.length))throw Error('STEP_INDEX');
  }
  if(!count)throw Error('STEP_EMPTY');
  const bytes=new Uint8Array(84+50*count),view=new DataView(bytes.buffer);
  bytes.set(new TextEncoder().encode('3D Print Optimizer - STEP converted to millimetres'));
  let at=84,written=0;
  for(const mesh of result.meshes){
    const p=mesh.attributes.position.array,ix=mesh.index.array;
    for(let i=0;i<ix.length;i+=3){
      const a=ix[i]*3,b=ix[i+1]*3,c=ix[i+2]*3;
      const ux=p[b]-p[a],uy=p[b+1]-p[a+1],uz=p[b+2]-p[a+2];
      const vx=p[c]-p[a],vy=p[c+1]-p[a+1],vz=p[c+2]-p[a+2];
      let nx=uy*vz-uz*vy,ny=uz*vx-ux*vz,nz=ux*vy-uy*vx;
      const length=Math.hypot(nx,ny,nz);if(length<1e-12)continue;
      nx/=length;ny/=length;nz/=length;
      const values=[nx,ny,nz,p[a],p[a+1],p[a+2],p[b],p[b+1],p[b+2],p[c],p[c+1],p[c+2]];
      for(let k=0;k<12;k++)view.setFloat32(at+k*4,values[k],true);
      at+=50;written++;
    }
  }
  if(!written)throw Error('STEP_EMPTY');
  view.setUint32(80,written,true);
  return bytes.slice(0,84+50*written);
}
root.stepMeshToStl=stepMeshToStl;
if(typeof module!=='undefined')module.exports=stepMeshToStl;
})(typeof self!=='undefined'?self:globalThis);
