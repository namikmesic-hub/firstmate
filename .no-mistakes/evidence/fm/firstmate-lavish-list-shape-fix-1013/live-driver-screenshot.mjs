import fs from 'node:fs';
const pages=await (await fetch('http://127.0.0.1:44932/json/list')).json();
const page=pages.find(p=>p.url==='http://127.0.0.1:44931/session/84db8a9291ab362c');
if(!page) throw Error('Lab page absent');
const ws=new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r=>ws.addEventListener('open',r,{once:true}));
const result=await new Promise((resolve,reject)=>{ws.addEventListener('message',({data})=>{const m=JSON.parse(data);if(m.id===1) m.error?reject(m.error):resolve(m.result)});ws.send(JSON.stringify({id:1,method:'Page.captureScreenshot',params:{format:'png',captureBeyondViewport:false}}));});
fs.writeFileSync(process.argv[2],Buffer.from(result.data,'base64'));ws.close();
console.log('Screenshot: '+process.argv[2]);
