function Result=FinalizeG4Seed1Acceptance_v2(Evidence,RuntimeRegistryPath,LedgerPath,ExpectedLedgerSHA256,AcceptanceManifestPath)
% Accept only sealed internal evidence; commit count=1 only after manifest hash.
arguments
    Evidence (1,1) struct
    RuntimeRegistryPath (1,1) string
    LedgerPath (1,1) string
    ExpectedLedgerSHA256 (1,1) string
    AcceptanceManifestPath (1,1) string
end
required={'GeneratedInternally','BuilderSHA256','ScientificRunId','RosterIndex','Seed','PayloadSHA256', ...
    'RandomModelVersion','SourceObjects','GateRows','AllRequiredGatesPass','InternalSealSHA256'};
for k=1:numel(required),assert(isfield(Evidence,required{k}),'G4Seed1RGEB:UntrustedEvidence','Evidence schema incomplete.');end
assert(logical(Evidence.GeneratedInternally),'G4Seed1RGEB:UntrustedEvidence','Anonymous/caller evidence is prohibited.');
assert(strcmpi(string(Evidence.InternalSealSHA256),sealLocal(Evidence)),'G4Seed1RGEB:EvidenceSealMismatch','Evidence seal mismatch.');
T=readtable(RuntimeRegistryPath,'FileType','text','Delimiter',',','TextType','string','VariableNamingRule','preserve','Encoding','UTF-8');
q=T.FunctionName=="BuildG4Seed1RealGateEvidence_v1";assert(nnz(q)==1,'G4Seed1RGEB:BuilderAuthorityMissing','Builder runtime authority missing.');
assert(strcmpi(string(Evidence.BuilderSHA256),string(T.ExpectedSHA256(q))),'G4Seed1RGEB:BuilderIdentityMismatch','Evidence builder SHA mismatch.');
rows=Evidence.GateRows;requiredGates=["PRE_POST_RARC","PAIR_POSITIVE","PAIR_AXIS","REALIZATION","RAW_CLOSURE", ...
    "OBSERVER_CLOSURE","METRIC_PIPELINE","D1_MCT","SIDE_ROUTE","MVCC","ZVDG","PROJECTOR","MIDD","RETENTION_COMPLETENESS"];
assert(numel(rows)==numel(requiredGates)&&isequal(sort(string({rows.GateId})),sort(requiredGates)), ...
    'G4Seed1RGEB:GateEvidenceIncomplete','Required gate evidence incomplete.');
for k=1:numel(rows)
    assert(string(rows(k).SourceRunId)==string(Evidence.ScientificRunId)&&double(rows(k).Seed)==double(Evidence.Seed), ...
        'G4Seed1RGEB:RunIdentityMismatch','Evidence row run identity mismatch.');
end
[Ledger,~]=UpdateG4Seed1AcceptanceLedger_v1(LedgerPath,ExpectedLedgerSHA256,"ASSERT_RUNNABLE",struct()); %#ok<ASGLU>
[manifestFolder,manifestBase]=fileparts(AcceptanceManifestPath);
evidencePath=fullfile(manifestFolder,manifestBase+"_GateEvidence.json");
writeJsonAtomicLocal(evidencePath,Evidence);evidenceFileSHA=sha256FileLocal(evidencePath);
allPass=all([rows.Pass]|[rows.LegalSpecialOutcome])&&logical(Evidence.AllRequiredGatesPass);
if ~allPass
    [~,newSHA]=UpdateG4Seed1AcceptanceLedger_v1(LedgerPath,ExpectedLedgerSHA256,"QUARANTINE",struct('ScientificRunId',Evidence.ScientificRunId));
    Result=struct('State',"QUARANTINED_HOLD",'G4_RESULT_COUNT',0,'LedgerSHA256',newSHA, ...
        'AcceptedPackageSHA256',"",'GateEvidencePath',evidencePath,'GateEvidenceSHA256',evidenceFileSHA);return
end
manifest=struct('Version',"G4_SEED1_ACCEPTANCE_MANIFEST_v1",'State',"ACCEPTED_G4_SCIENCE", ...
    'ScientificRunId',Evidence.ScientificRunId,'RosterIndex',Evidence.RosterIndex,'Seed',Evidence.Seed, ...
    'PayloadSHA256',Evidence.PayloadSHA256,'RandomModelVersion',Evidence.RandomModelVersion, ...
    'EvidenceSealSHA256',Evidence.InternalSealSHA256,'GateEvidencePath',evidencePath, ...
    'GateEvidenceSHA256',evidenceFileSHA,'GateCount',numel(rows),'AllGatesPass',true, ...
    'CreatedUTC',string(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
writeJsonAtomicLocal(AcceptanceManifestPath,manifest);pkgSHA=sha256FileLocal(AcceptanceManifestPath);
[~,newSHA]=UpdateG4Seed1AcceptanceLedger_v1(LedgerPath,ExpectedLedgerSHA256,"ACCEPT", ...
    struct('ScientificRunId',Evidence.ScientificRunId,'AcceptedPackageSHA256',pkgSHA));
Result=struct('State',"ACCEPTED_G4_SCIENCE",'G4_RESULT_COUNT',1,'LedgerSHA256',newSHA, ...
    'AcceptedPackageSHA256',pkgSHA,'GateEvidencePath',evidencePath, ...
    'GateEvidenceSHA256',evidenceFileSHA,'PairingAuthority',"ONE_TO_ONE_PROVEN_FOR_SEED_1");
end
function s=sealLocal(E)
E.InternalSealSHA256="";md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(uint8(unicode2native(jsonencode(E),'UTF-8'))),'uint8');s=string(lower(reshape(dec2hex(d,2).',1,[])));
end
function writeJsonAtomicLocal(path,S)
folder=fileparts(path);if ~isfolder(folder),mkdir(folder);end;tmp=fullfile(folder,".accept_"+string(char(java.util.UUID.randomUUID()))+".tmp");fid=fopen(tmp,'w','n','UTF-8');assert(fid>0);fwrite(fid,jsonencode(S,'PrettyPrint',true),'char');fclose(fid);[ok,msg]=movefile(tmp,path,'f');assert(ok,'G4Seed1DSAL:AtomicCommitFailed','%s',msg);
end
function h=sha256FileLocal(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
