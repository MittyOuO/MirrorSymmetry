function DnumTable = LookupFrozenDnum_v1(CsvPath,ExpectedSHA256,ExpectedBytes)
%LookupFrozenDnum_v1 Exact frozen lookup only; recomputation is prohibited.
arguments
    CsvPath (1,1) string
    ExpectedSHA256 (1,1) string
    ExpectedBytes (1,1) double {mustBeInteger,mustBePositive}
end
assert(exist(CsvPath,'file')==2,'G4P0v5:DnumSourceMissing','Frozen D_num CSV missing.');
info=dir(CsvPath);
assert(info.bytes==ExpectedBytes,'G4P0v5:DnumByteMismatch','Frozen D_num byte mismatch.');
actual=sha256FileLocal(CsvPath);
assert(strcmp(actual,lower(char(ExpectedSHA256))),'G4P0v5:DnumSHAMismatch', ...
    'Frozen D_num SHA mismatch; regeneration is forbidden.');
T=readtable(CsvPath,'TextType','string','VariableNamingRule','preserve');
expectedC6=["WindowEnergy";"MeanRL";"P50RL";"P95RL";"t50";"t90"; ...
    "Peak prominence";"Fixed-neighborhood peak energy";"Major-peak timing";"Major-peak amplitude"];
expectedG4=["WindowEnergy";"MeanRL";"P50RL";"P95RL";"t50";"t90"; ...
    "peak prominence";"Fixed-neighborhood peak energy";"Major-peak timing";"Major-peak amplitude"];
assert(height(T)==10 && isequal(T.QoI,expectedC6),'G4P0v5:DnumQoIIdentityMismatch', ...
    'Frozen C6 QoI identifiers/order do not match the explicit v1 map.');
assert(all(isfinite(T.D_num) & T.D_num>0),'G4P0v5:DnumInvalidFrozenValue');
T.G4QoI=expectedG4;
T.DnumMode=repmat("FROZEN_LOOKUP_ONLY",height(T),1);
T.DnumRecomputationInG4=repmat("PROHIBITED",height(T),1);
T.DnumReselectionInG4=repmat("PROHIBITED",height(T),1);
DnumTable=T;
end

function hex=sha256FileLocal(path)
fid=fopen(path,'rb'); assert(fid>=0); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,'*uint8'); md=java.security.MessageDigest.getInstance('SHA-256');
digest=typecast(md.digest(bytes),'uint8'); hex=lower(reshape(dec2hex(digest,2).',1,[]));
end
