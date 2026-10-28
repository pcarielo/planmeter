'use strict';
const net=require('node:net');
const dns=require('node:dns').promises;
const approved=new Set(['api.kimi.com','auth.kimi.com','chatgpt.com','auth.openai.com','api.anthropic.com','platform.claude.com','console.anthropic.com','claude.ai','api.z.ai']);
function publicAddress(ip){
  if(net.isIP(ip)===4){const [a,b]=ip.split('.').map(Number);return a!==0&&a!==10&&a!==127&&a<224&&!(a===169&&b===254)&&!(a===172&&b>=16&&b<=31)&&!(a===192&&b===168)&&!(a===100&&b>=64&&b<=127)&&!(a===198&&(b===18||b===19));}
  return net.isIP(ip)===6&&/^[23][0-9a-f]{3}:/i.test(ip);
}
function authority(line,hosts){
  const match=/^CONNECT ([a-z0-9.-]+):443 HTTP\/1\.[01]$/i.exec(line);
  return match&&hosts.has(match[1].toLowerCase())?match[1].toLowerCase():null;
}
async function createGateway(hosts,lookup=dns.lookup){
  if(!hosts.length||hosts.some(h=>!approved.has(h)))throw new Error('invalid_hosts');
  const allowed=new Set(hosts),sockets=new Set(),servers=[];let closing=false,ready=false;
  function reject(socket){socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n',()=>socket.destroy());}
  function handle(socket){
    if(!ready||closing||sockets.size>=16){socket.destroy();return;}
    sockets.add(socket);socket.once('close',()=>sockets.delete(socket));socket.on('error',()=>socket.destroy());
    socket.setTimeout(65000,()=>socket.destroy());let header=Buffer.alloc(0);
    const onData=async chunk=>{
      header=Buffer.concat([header,chunk]);
      if(header.length>16384){socket.destroy();return;}
      const end=header.indexOf('\r\n\r\n');if(end<0)return;
      socket.removeListener('data',onData);socket.pause();
      const host=authority(header.subarray(0,end).toString('ascii').split('\r\n')[0],allowed);
      if(!host){reject(socket);return;}
      const remainder=header.subarray(end+4);header=Buffer.alloc(0);
      let addresses,timer;
      try{addresses=await Promise.race([lookup(host,{all:true}),new Promise((_,no)=>{timer=setTimeout(()=>no(new Error('dns_timeout')),4000);})]);}
      catch{reject(socket);return;}finally{clearTimeout(timer);}
      if(closing||socket.destroyed)return;
      if(!addresses.length||addresses.some(a=>!publicAddress(a.address))){reject(socket);return;}
      // Pin the checked address. No second DNS lookup can redirect the tunnel to a private host.
      const address=addresses.find(a=>a.family===4)||addresses[0];
      const upstream=net.connect({host:address.address,family:address.family,port:443});sockets.add(upstream);
      upstream.once('close',()=>sockets.delete(upstream));upstream.on('error',()=>{socket.destroy();upstream.destroy();});
      socket.once('close',()=>upstream.destroy());upstream.setTimeout(65000,()=>upstream.destroy());
      upstream.once('connect',()=>{
        if(closing||socket.destroyed){upstream.destroy();return;}
        socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        if(remainder.length)upstream.write(remainder);
        socket.pipe(upstream);upstream.pipe(socket);socket.resume();
      });
    };
    socket.on('data',onData);
  }
  async function reserve(host,port){
    // Reservation is the availability check; relaying is enabled only after both addresses succeed.
    const server=net.createServer(handle);servers.push(server);
    await new Promise((yes,no)=>{server.once('error',no);server.listen({host,port,exclusive:true},yes);});
    return server.address().port;
  }
  function close(){closing=true;for(const socket of sockets)socket.destroy();for(const server of servers)server.close();}
  try{const port=await reserve('127.0.0.1',0);await reserve('::1',port);ready=true;return {port,close};}
  catch(error){close();throw new Error(error.code==='EADDRINUSE'?'port_in_use':'listener_unavailable');}
}
module.exports={publicAddress,authority,createGateway};
if(require.main===module){
  (async()=>{
    try{
      const nodeMajor=Number(process.versions.node.split('.')[0]);
      if(!Number.isInteger(nodeMajor)||nodeMajor<18) throw new Error('node_version');
      const gateway=await createGateway(JSON.parse(process.argv[2]||'[]'));
      process.stdout.write(JSON.stringify({port:gateway.port,nodeMajor})+'\n');
      const close=()=>{gateway.close();process.exitCode=0;};
      process.stdin.resume();process.stdin.on('end',close);process.on('SIGTERM',close);process.on('SIGINT',close);
    }catch(error){process.stdout.write(JSON.stringify({error:error.message==='node_version'?'node_version':'relay_unavailable'})+'\n');process.exitCode=1;}
  })();
}
