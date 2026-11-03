function Report=ResolveG4RuntimeAuthorityClosure_v1(RegistryCsv,OutputStem,Phase)
% Fresh-process runtime authority resolution closure. Fails closed.
arguments
    RegistryCsv (1,1) string
    OutputStem (1,1) string
    Phase (1,1) string
end
T=readtable(RegistryCsv,'FileType','text','Delimiter',',','TextType','string','VariableNamingRule','preserve','Encoding','UTF-8');n=height(T);rows=repmat(struct('Phase',"",'FunctionName',"", ...
    'ExpectedPath',"",'ResolvedPath',"",'AllResolvedPaths',"",'ExpectedSHA256',"", ...
    'ResolvedSHA256',"",'ExpectedBytes',0,'ResolvedBytes',0,'ResolutionCount',0, ...
    'Unresolved',false,'Shadowed',false,'PathMatch',false,'SHAMatch',false,'BytesMatch',false,'PASS',false),n,1);
for k=1:n
    fn=T.FunctionName(k);w=which(char(fn),'-all');
    if isempty(w),allp=strings(0,1);elseif ischar(w),allp=string(cellstr(w));else,allp=string(w);end
    allp=allp(strlength(allp)>0);unresolved=isempty(allp);shadowed=numel(allp)~=1;
    resolved="";rh="";rb=0;if ~unresolved,resolved=allp(1);if isfile(resolved),rh=sha256Local(resolved);d=dir(resolved);rb=d.bytes;end,end
    ep=canonicalLocal(T.ExpectedPath(k));rp=canonicalLocal(resolved);pathMatch=~unresolved&&strcmpi(ep,rp);
    shaMatch=~unresolved&&strcmpi(rh,T.ExpectedSHA256(k));bytesMatch=~unresolved&&rb==T.ExpectedBytes(k);pass=~unresolved&&~shadowed&&pathMatch&&shaMatch&&bytesMatch;
    rows(k)=struct('Phase',Phase,'FunctionName',fn,'ExpectedPath',T.ExpectedPath(k),'ResolvedPath',resolved, ...
        'AllResolvedPaths',strjoin(allp,' || '),'ExpectedSHA256',T.ExpectedSHA256(k),'ResolvedSHA256',rh, ...
        'ExpectedBytes',T.ExpectedBytes(k),'ResolvedBytes',rb,'ResolutionCount',numel(allp), ...
        'Unresolved',unresolved,'Shadowed',shadowed,'PathMatch',pathMatch,'SHAMatch',shaMatch,'BytesMatch',bytesMatch,'PASS',pass);
end
Report=struct('Version','G4_RUNTIME_AUTHORITY_RESOLUTION_CLOSURE_v1','Phase',Phase,'Rows',rows, ...
    'AllPass',all([rows.PASS]),'FailClosedOnShadowUnresolvedWrongSHA',true,'ScientificExecution',false,'G4_RESULT_COUNT',0);
writetable(struct2table(rows),OutputStem+".csv");fid=fopen(OutputStem+".json",'w');assert(fid>0);c=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',jsonencode(Report,'PrettyPrint',true)); %#ok<NASGU>
assert(Report.AllPass,'G4PreExec:RARCFailClosed','Runtime authority resolution closure failed.');
end
function p=canonicalLocal(x)
if strlength(x)==0,p="";return,end
try,p=string(char(java.io.File(char(x)).getCanonicalPath()));catch,p=string(x);end
end
function h=sha256Local(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
