function Out=LoadG4FrozenControlVectors_v1(A)
% Read only the five SHA-frozen envelope sources and construct frozen directions.
arguments
    A (1,1) struct
end
names={'Production','F50','R60','A005','Jmin'};
for k=1:numel(names)
    n=names{k};assert(isfield(A,n)&&isfile(string(A.(n).Path)),'G4Seed1Vector:SourceMissing','Missing %s source.',n);
    assert(strcmpi(sha256FileLocal(string(A.(n).Path)),string(A.(n).SHA256)),'G4Seed1Vector:SourceSHAMismatch','%s source SHA mismatch.',n);
end
P=readEnvelopeLocal(A.Production.Path,"FormalFs256000");F512=readEnvelopeLocal(A.Production.Path,"FormalFs512000");
F50=readEnvelopeLocal(A.F50.Path,"");R60=readEnvelopeLocal(A.R60.Path,"");A005=readEnvelopeLocal(A.A005.Path,"");J=readEnvelopeLocal(A.Jmin.Path,"");
assert(isequal(P.TimeS,F512.TimeS,F50.TimeS,R60.TimeS,A005.TimeS,J.TimeS),'G4Seed1Vector:TimeGridMismatch','Frozen envelope time grids differ.');
u=@(x)x/norm(x);
up=u(P.Value);uf=u(F50.Value);ud=u(R60.Value);ua=u(A005.Value);u512=u(F512.Value);uj=u(J.Value);
V=[uf-up,ud-up,ua-up,u512-up];iC5=uj-ud-ua+up;
assert(size(V,1)==6000&&rank(V)==4,'G4Seed1Vector:RankMismatch','Frozen control matrix must be 6000x4 rank 4.');
Out=struct('V',V,'iC5',iC5,'TimeS',P.TimeS,'Rank',4,'SourceAuthority',A, ...
    'ScientificModelVectorGenerated',false);
end
function E=readEnvelopeLocal(path,label)
T=readtable(string(path),'FileType','text','Delimiter',',','TextType','string','VariableNamingRule','preserve','Encoding','UTF-8');
if strlength(label)>0,T=T(string(T.Label)==label,:);end
assert(height(T)==6000&&all(ismember(["TimeS","RMSAmplitude"],string(T.Properties.VariableNames))),'G4Seed1Vector:SchemaMismatch','Envelope schema mismatch.');
E=struct('TimeS',double(T.TimeS),'Value',double(T.RMSAmplitude));
end
function h=sha256FileLocal(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
