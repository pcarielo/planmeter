// Availability probes held open as fixtures; no request data is collected.
const net = require('node:net');
const {spawn} = require('node:child_process');
const executable=process.argv[2];
if(!executable){console.error('Missing fixture executable');process.exit(2);}
const probes=[];
function reserve(host){
  return new Promise((resolve,reject)=>{
    const server=net.createServer(socket=>socket.destroy());probes.push(server);
    server.once('error',error=>reject(new Error(error.code==='EADDRINUSE' ? 'Fixture port is already in use; no client started.' : 'Loopback fixture unavailable: '+error.code)));
    server.listen({host,port:0,exclusive:true},()=>resolve(server.address().port));
  });
}
(async()=>{
  try{
    const port4=await reserve('127.0.0.1');const port6=await reserve('::1');
    const child=spawn(executable,['--self-test'],{stdio:'inherit',env:{...process.env,PLANMETER_TEST_PROBE_PORT:String(port4),PLANMETER_TEST_PROBE_IPV6_PORT:String(port6)}});
    const timer=setTimeout(()=>child.kill('SIGKILL'),60000);
    const close=()=>{clearTimeout(timer);for(const server of probes)server.close();};
    child.once('error',()=>{close();process.exitCode=1;});
    child.once('exit',(code,signal)=>{close();process.exitCode=signal?1:(code??1);});
  }catch(error){console.error(error.message);for(const server of probes)server.close();process.exitCode=1;}
})();
