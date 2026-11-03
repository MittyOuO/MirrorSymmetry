function Audit=ValidateG4Seed1AuthorizationArtifact_v1(ArtifactPath,ExpectedArtifactSHA256,Bindings,AllowSyntheticFixture)
% Validate separate SHA-bound researcher authorization before traversal.
arguments
    ArtifactPath (1,1) string
    ExpectedArtifactSHA256 (1,1) string
    Bindings (1,1) struct
    AllowSyntheticFixture (1,1) logical = false
end
assert(isfile(ArtifactPath),'G4Seed1AuthArtifact:Missing','Authorization artifact is missing.');
actualSHA=sha256FileLocal(ArtifactPath);
assert(strcmpi(actualSHA,ExpectedArtifactSHA256),'G4Seed1AuthArtifact:SHA_MISMATCH','Authorization artifact SHA mismatch.');
A=jsondecode(fileread(ArtifactPath));
required={'AuthorizationVersion','AuthorizationStatus','RosterIndex','Seed','SeedPayloadSHA256', ...
    'RandomModelVersion','ScienceRunnerSHA256','AuthorizationContractSHA256','RuntimeRegistrySHA256', ...
    'FrozenDnumSHA256','NumericalGeometryContractSHA256','IssueUTC','IssuerRole','AuthorizationId'};
for k=1:numel(required),assert(isfield(A,required{k}),'G4Seed1AuthArtifact:Malformed','Missing artifact field %s.',required{k});end
isSynthetic=isfield(A,'SyntheticFixture')&&logical(A.SyntheticFixture);
if isSynthetic
    assert(AllowSyntheticFixture,'G4Seed1AuthArtifact:NotAuthorized','Synthetic fixture cannot authorize science.');
    assert(strcmp(string(A.IssuerRole),"RESEARCHER_SYNTHETIC_FIXTURE"),'G4Seed1AuthArtifact:NotAuthorized','Invalid fixture role.');
else
    assert(strcmp(string(A.IssuerRole),"RESEARCHER"),'G4Seed1AuthArtifact:NotAuthorized','Issuer role is not RESEARCHER.');
end
assert(strcmp(string(A.AuthorizationStatus),"AUTHORIZE_EXACTLY_SEED_1"),'G4Seed1AuthArtifact:NotAuthorized','Exact authorization status not present.');
assert(double(A.RosterIndex)==1&&isaValueUint32Local(A.Seed,Bindings.Seed), ...
    'G4Seed1AuthArtifact:SeedIdentityMismatch','Roster index or seed mismatch.');
assert(strcmpi(string(A.SeedPayloadSHA256),string(Bindings.PayloadSHA256))&& ...
    double(A.RandomModelVersion)==double(Bindings.RandomModelVersion), ...
    'G4Seed1AuthArtifact:SeedIdentityMismatch','Payload SHA or RMV mismatch.');
assert(strcmpi(string(A.ScienceRunnerSHA256),string(Bindings.ScienceRunnerSHA256)), ...
    'G4Seed1AuthArtifact:RunnerMismatch','Runner SHA mismatch.');
assert(strcmpi(string(A.AuthorizationContractSHA256),string(Bindings.AuthorizationContractSHA256)), ...
    'G4Seed1AuthArtifact:ContractMismatch','Contract SHA mismatch.');
assert(strcmpi(string(A.RuntimeRegistrySHA256),string(Bindings.RuntimeRegistrySHA256)), ...
    'G4Seed1AuthArtifact:ContractMismatch','Runtime registry SHA mismatch.');
assert(strcmpi(string(A.FrozenDnumSHA256),string(Bindings.FrozenDnumSHA256))&& ...
    strcmpi(string(A.NumericalGeometryContractSHA256),string(Bindings.NumericalGeometryContractSHA256)), ...
    'G4Seed1AuthArtifact:ContractMismatch','Frozen numerical authority mismatch.');
assert(strlength(string(A.AuthorizationId))>0&&strlength(string(A.IssueUTC))>0, ...
    'G4Seed1AuthArtifact:Malformed','Authorization id/time missing.');
Audit=struct('PASS',true,'ArtifactPath',ArtifactPath,'ArtifactSHA256',actualSHA, ...
    'AuthorizationId',string(A.AuthorizationId),'SyntheticFixture',isSynthetic, ...
    'TraversalAuthorization',~isSynthetic,'Status',string(A.AuthorizationStatus));
end
function tf=isaValueUint32Local(x,expected)
tf=isnumeric(x)&&isscalar(x)&&isfinite(double(x))&&double(x)>=0&&double(x)<=double(intmax('uint32'))&&double(x)==double(expected)&&double(x)==floor(double(x));
end
function h=sha256FileLocal(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
