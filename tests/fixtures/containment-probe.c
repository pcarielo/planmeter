#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
int main(int argc,char **argv) {
    int ipv6=argc>2 && atoi(argv[2])==6;
    int fd=socket(ipv6?AF_INET6:AF_INET,SOCK_STREAM,0);
    if(fd<0){puts("unreachable");return 0;}
    int port=argc>1?atoi(argv[1]):443,result;
    if(argc>2 && argv[2][0]=='p') {const char *proxy=getenv("HTTPS_PROXY");const char *colon=proxy?strrchr(proxy,':'):NULL;if(!colon){puts("unreachable");close(fd);return 0;}port=atoi(colon+1);}
    if(ipv6){
        struct sockaddr_in6 addr={0};addr.sin6_len=sizeof(addr);addr.sin6_family=AF_INET6;addr.sin6_port=htons(port);
        inet_pton(AF_INET6,"::1",&addr.sin6_addr);result=connect(fd,(struct sockaddr*)&addr,sizeof(addr));
    }else{
        struct sockaddr_in addr={0};addr.sin_len=sizeof(addr);addr.sin_family=AF_INET;addr.sin_port=htons(port);
        inet_pton(AF_INET,"127.0.0.1",&addr.sin_addr);result=connect(fd,(struct sockaddr*)&addr,sizeof(addr));
    }
    close(fd);puts(result==0?"connected":"unreachable");return 0;
}
