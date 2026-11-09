'use strict';
const binary=Uint8Array.from(atob(STEP_WASM_BASE64),c=>c.charCodeAt(0));
let engine;
occtimportjs({wasmBinary:binary,print:()=>{},printErr:()=>{}}).then(value=>{
  engine=value;postMessage({type:'ready'});
}).catch(()=>postMessage({type:'error',code:'STEP_ENGINE'}));
onmessage=function(event){
  try{
    const bytes=new Uint8Array(event.data);
    if(!engine||bytes.length<20||bytes.length>20*1024*1024)throw Error('STEP_INPUT');
    const result=engine.ReadStepFile(bytes,{linearUnit:'millimeter',linearDeflectionType:'absolute_value',linearDeflection:0.05,angularDeflection:0.25});
    const stl=stepMeshToStl(result);
    postMessage({type:'result',buffer:stl.buffer},[stl.buffer]);
  }catch(error){postMessage({type:'error',code:error.message==='STEP_COMPLEX'?'STEP_COMPLEX':'STEP_INVALID'});}
};
