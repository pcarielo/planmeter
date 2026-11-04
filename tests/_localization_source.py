"""Swift message-literal scanner used only by catalog checks."""
import re
def dec(s):
 s=re.sub(r'\\u\{([0-9a-fA-F]+)\}',lambda m:chr(int(m.group(1),16)),s)
 return re.sub(r'\\([nrt0"\\])',lambda m:{'n':'\n','r':'\r','t':'\t','0':'\0','"':'"','\\':'\\'}[m.group(1)],s)
def string(s,i):
 # normal Swift string; interpolation expressions may contain nested strings.
 start=i;i+=1;parts=[];expr=[];mark=i
 while i<len(s):
  if s[i]=='\\':
   if i+1<len(s) and s[i+1]=='(':
    parts.append(dec(s[mark:i]));j=i+2;depth=1;k=j
    while k<len(s) and depth:
     if s[k]=='"':k=string(s,k)[0];continue
     if s[k]=='(':depth+=1
     elif s[k]==')':depth-=1
     k+=1
    expr.append({'source':s[j:k-1],'start':j,'end':k-1});i=k;mark=i;continue
   i+=2;continue
  if s[i]=='"':
   parts.append(dec(s[mark:i]));return i+1,parts,expr
  i+=1
 return i,[],[]
def scan(s):
 i=0
 while i<len(s):
  if s.startswith('//',i):
   j=s.find('\n',i);i=len(s) if j<0 else j+1;continue
  if s.startswith('/*',i):
   j=s.find('*/',i+2);i=len(s) if j<0 else j+2;continue
  if s[i]=='#' and i+1<len(s) and s[i+1]=='"':
   j=s.find('"#',i+2);i=len(s) if j<0 else j+2;continue
  if s.startswith('"""',i):
   j=s.find('"""',i+3);i=len(s) if j<0 else j+3;continue
  if s[i]=='"':
   end,parts,expr=string(s,i)
   if parts:
    yield i,end,parts,expr
    for e in expr:
     for a,b,nparts,nexpr in scan(e['source']):yield e['start']+a,e['start']+b,nparts,nexpr
   i=end;continue
  i+=1

