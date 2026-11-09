'use strict';
let worker,workerUrl,input,offset=0,output=null,sent=0;
const send=value=>StepBridge.postMessage(JSON.stringify(value));
window.stepCancel=function(){if(worker){worker.terminate();worker=null;}if(workerUrl){URL.revokeObjectURL(workerUrl);workerUrl=null;}input=null;output=null;};
window.stepBegin=function(size){
  if(!Number.isSafeInteger(size)||size<20||size>20*1024*1024)throw Error('STEP_INPUT');
  input=new Uint8Array(size);offset=0;
};
window.stepAppend=function(encoded){
  const chunk=atob(encoded);if(!input||chunk.length>24576||offset+chunk.length>input.length)throw Error('STEP_CHUNK');
  for(let i=0;i<chunk.length;i++)input[offset++]=chunk.charCodeAt(i);
};
window.stepConvert=function(){
  if(!worker||!input||offset!==input.length)throw Error('STEP_INPUT');
  worker.postMessage(input.buffer,[input.buffer]);input=null;
};
window.stepReadNext=function(){
  if(!output)return;
  if(sent===output.length){output=null;send({type:'done'});return;}
  const end=Math.min(sent+24576,output.length),part=output.subarray(sent,end);
  let binary='';for(let i=0;i<part.length;i++)binary+=String.fromCharCode(part[i]);
  const start=sent;sent=end;send({type:'chunk',offset:start,data:btoa(binary)});
};
try{
  workerUrl=URL.createObjectURL(new Blob([window.stepWorkerSource],{type:'text/javascript'}));
  worker=new Worker(workerUrl);window.stepWorkerSource=null;
  worker.onmessage=function(event){
    const value=event.data;
    if(value.type==='ready'&&workerUrl){URL.revokeObjectURL(workerUrl);workerUrl=null;}
    if(value.type==='result'){
      output=new Uint8Array(value.buffer);sent=0;
      if(output.length>25000084){stepCancel();send({type:'error',code:'STEP_COMPLEX'});return;}
      send({type:'begin',bytes:output.length});
    }else send(value);
  };
  worker.onerror=function(){stepCancel();send({type:'error',code:'STEP_ENGINE'});};
}catch(_){send({type:'error',code:'STEP_ENGINE'});}
