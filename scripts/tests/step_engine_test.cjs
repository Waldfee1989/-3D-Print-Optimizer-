const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
const adapter=require(path.join(root,'assets/step/mesh_to_stl.js'));
const engine=path.join(root,'build/step-importer');
const params={linearUnit:'millimeter',linearDeflectionType:'absolute_value',linearDeflection:0.05,angularDeflection:0.25};
function bounds(bytes){
 const v=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];
 const count=v.getUint32(80,true);assert.equal(bytes.length,84+50*count);assert.ok(count>0);
 for(let i=0;i<count;i++)for(let j=0;j<3;j++)for(let a=0;a<3;a++){
  const n=v.getFloat32(84+i*50+12+j*12+a*4,true);assert.ok(Number.isFinite(n));lo[a]=Math.min(lo[a],n);hi[a]=Math.max(hi[a],n);
 }
 return hi.map((v,i)=>v-lo[i]);
}
(async()=>{
 const occt=await require(path.join(engine,'occt-import-js.js'))({print:()=>{},printErr:()=>{}});
 for(const unit of ['mm','in','m']){
  const result=occt.ReadStepFile(fs.readFileSync(path.join(engine,`fixtures/cube-units/cube-${unit}.step`)),params);
  const size=bounds(adapter(result));for(const n of size)assert.ok(Math.abs(n-1000)<0.001,`${unit}: ${size}`);
 }
 const cube=adapter(occt.ReadStepFile(fs.readFileSync(path.join(engine,'fixtures/simple-basic-cube/cube.stp')),params));
 assert.equal(require('node:crypto').createHash('sha256').update(cube).digest('hex'),'1ceead55be47bec58e3397bae5e7017b1b8e72863a8f65bb8649f40d56d5af63');
 const assembly=occt.ReadStepFile(fs.readFileSync(path.join(engine,'fixtures/cax-if/as1_pe_203.stp')),params);
 assert.equal(assembly.meshes.length,18);bounds(adapter(assembly));
 assert.throws(()=>adapter({success:false}));
 const mesh={attributes:{position:{array:[0,0,0,1,0,0,0,1,0]}},index:{array:[0,1,2]}};
 assert.equal(adapter({success:true,meshes:[mesh]}).length,134);
 assert.throws(()=>adapter({success:true,meshes:[{...mesh,index:{array:[0,1,3]}}]}));
 assert.throws(()=>adapter({success:true,meshes:[{...mesh,index:{array:Array(1500003).fill(0)}}]}));
 assert.throws(()=>adapter({success:true,meshes:[{...mesh,attributes:{position:{array:[NaN,0,0]}}}]}));
 if(process.argv[2]){
  const result=occt.ReadStepFile(fs.readFileSync(process.argv[2]),params),bytes=adapter(result);
  console.log(JSON.stringify({localFixture:true,meshes:result.meshes.length,triangles:new DataView(bytes.buffer).getUint32(80,true),millimetres:bounds(bytes)}));
 }
 console.log('STEP engine: units, assemblies, complete STL output and malformed/complex geometry passed.');
})().catch(e=>{console.error(e);process.exit(1)});
