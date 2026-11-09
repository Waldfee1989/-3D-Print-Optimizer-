const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.STEP_PLAYWRIGHT||'playwright-core');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.STEP_CHROME||'/usr/bin/google-chrome',args:['--no-sandbox']});
 try{
  const page=await browser.newPage(),network=[];
  page.on('console',message=>{if(message.type()==='error')console.error('Local browser:',message.text());});
  page.on('pageerror',error=>console.error('Local page:',error.message));
  page.on('request',request=>{if(/^https?:/.test(request.url()))network.push(request.url());});
  const file=fs.readFileSync(process.argv[2]||path.join(root,'build/step-importer/fixtures/simple-basic-cube/cube.stp'));
  let resolve,reject;const done=new Promise((r,j)=>{resolve=r;reject=j;});const chunks=[];let received=0,expected=0,acks=0;
  await page.exposeFunction('nativeStepMessage',async text=>{
   try{
    const m=JSON.parse(text);
    if(m.type==='ready'){
     await page.evaluate(n=>window.stepBegin(n),file.length);
     for(let i=0;i<file.length;i+=24576)await page.evaluate(s=>window.stepAppend(s),file.subarray(i,i+24576).toString('base64'));
     await page.evaluate(()=>window.stepConvert());
    }else if(m.type==='begin'){expected=m.bytes;await page.evaluate(()=>window.stepReadNext());}
    else if(m.type==='chunk'){
     assert.equal(m.offset,received);assert.ok(m.data.length<=32768);
     const chunk=Buffer.from(m.data,'base64');chunks.push(chunk);received+=chunk.length;acks++;
     await page.evaluate(()=>window.stepReadNext());
    }else if(m.type==='done'){assert.equal(received,expected);resolve(Buffer.concat(chunks));}
    else if(m.type==='error')reject(Error(m.code));
   }catch(e){reject(e);}
  });
  await page.addInitScript(()=>{window.StepBridge={postMessage:s=>window.nativeStepMessage(s)};});
  await page.goto(pathToFileURL(path.join(root,'assets/step/index.html')).href);
  let timeout;const stl=await Promise.race([done,new Promise((_,j)=>{timeout=setTimeout(()=>j(Error('STEP browser timeout')),45000);})]);clearTimeout(timeout);
  assert.equal(stl.length,84+stl.readUInt32LE(80)*50);assert.ok(acks>0);assert.deepEqual(network,[]);
  await page.evaluate(()=>window.stepCancel());
  assert.equal(await page.evaluate(()=>worker===null&&input===null&&output===null),true);
  console.log(`Offline browser bridge passed: ${stl.readUInt32LE(80)} triangles, ${acks} acknowledged chunks, no network.`);
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
