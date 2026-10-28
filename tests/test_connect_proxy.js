'use strict';
const assert=require('node:assert/strict'),net=require('node:net');
const {publicAddress,authority,createGateway}=require('../app/Resources/insight-connect-proxy.js');
for(const address of ['127.0.0.1','10.1.2.3','192.168.1.2','172.16.0.1','169.254.169.254','100.64.0.8','::1','::ffff:127.0.0.1','fe80::1','fc00::1'])assert.equal(publicAddress(address),false);
assert.equal(publicAddress('8.8.8.8'),true);assert.equal(publicAddress('2606:4700::1111'),true);
const hosts=new Set(['api.kimi.com']);
assert.equal(authority('CONNECT api.kimi.com:443 HTTP/1.1',hosts),'api.kimi.com');
for(const line of ['CONNECT 127.0.0.1:443 HTTP/1.1','CONNECT api.kimi.com:80 HTTP/1.1','CONNECT evil.example:443 HTTP/1.1','GET https://api.kimi.com/ HTTP/1.1'])assert.equal(authority(line,hosts),null);
(async()=>{
 let lookups=0;
 const gateway=await createGateway(['api.kimi.com'],async()=>{lookups++;return [{address:'127.0.0.1',family:4}];});
 const ask=line=>new Promise((yes,no)=>{
  const socket=net.connect({host:'127.0.0.1',port:gateway.port},()=>socket.write(line+'\r\n\r\n'));let result='';
  socket.on('data',data=>result+=data);socket.on('end',()=>yes(result));socket.on('error',no);socket.setTimeout(3000,()=>{socket.destroy();no(new Error('fixture timeout'));});
 });
 try{
  assert.match(await ask('CONNECT evil.example:443 HTTP/1.1'),/403/);assert.equal(lookups,0);
  assert.match(await ask('CONNECT api.kimi.com:443 HTTP/1.1'),/403/);assert.equal(lookups,1);
 }finally{gateway.close();}
 console.log('PASS restricted proxy: fixed hosts, port443, private-address rejection; no upstream connection');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
