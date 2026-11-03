function [Ledger,NewSHA256]=UpdateG4Seed1AcceptanceLedger_v1(LedgerPath,ExpectedCurrentSHA256,Action,Context)
% Transaction-safe durable per-seed state machine.
arguments
    LedgerPath (1,1) string
    ExpectedCurrentSHA256 (1,1) string
    Action (1,1) string
    Context (1,1) struct = struct()
end
assert(isfile(LedgerPath),'G4Seed1DSAL:LedgerMissing','Ledger is missing.');
actual=sha256FileLocal(LedgerPath);
assert(strcmpi(actual,ExpectedCurrentSHA256),'G4Seed1DSAL:LedgerSHAMismatch','Ledger SHA mismatch.');
try,Ledger=jsondecode(fileread(LedgerPath));catch,error('G4Seed1DSAL:MalformedLedger','Ledger JSON is malformed.');end
allowed=["NOT_RUN","GENERATED_UNACCEPTED","ACCEPTED_G4_SCIENCE","QUARANTINED_HOLD"];
assert(isfield(Ledger,'State')&&any(string(Ledger.State)==allowed),'G4Seed1DSAL:MalformedState','Ledger state is invalid.');
assert(double(Ledger.RosterIndex)==1&&double(Ledger.Seed)==262709171,'G4Seed1DSAL:MalformedIdentity','Ledger identity mismatch.');
state=string(Ledger.State);
if Action=="ASSERT_RUNNABLE"
    assert(state~="ACCEPTED_G4_SCIENCE",'G4Seed1DSAL:AcceptedSeedCannotRerun','Accepted seed cannot be normally rerun.');
    assert(state~="QUARANTINED_HOLD",'G4Seed1DSAL:RepairAuthorizationRequired','Quarantined seed requires the frozen RRB route.');
    NewSHA256=actual;return
end
runId=requiredContextLocal(Context,'ScientificRunId');
if Action=="MARK_GENERATED"
    assert(state=="NOT_RUN",'G4Seed1DSAL:InvalidTransition','Only NOT_RUN may transition to GENERATED_UNACCEPTED.');
    Ledger.State='GENERATED_UNACCEPTED';Ledger.G4_RESULT_COUNT=0;Ledger.ScientificRunId=char(string(runId));
elseif Action=="ACCEPT"
    assert(state~="ACCEPTED_G4_SCIENCE",'G4Seed1DSAL:AcceptedSeedCannotRerun','Acceptance count cannot increment twice.');
    assert(state=="GENERATED_UNACCEPTED",'G4Seed1DSAL:InvalidTransition','Acceptance requires GENERATED_UNACCEPTED.');
    assert(strcmp(string(Ledger.ScientificRunId),string(runId)),'G4Seed1DSAL:RunIdentityMismatch','Ledger run id mismatch.');
    pkg=requiredContextLocal(Context,'AcceptedPackageSHA256');
    assert(strlength(string(pkg))==64,'G4Seed1DSAL:AcceptancePackageMissing','Acceptance package SHA missing.');
    Ledger.State='ACCEPTED_G4_SCIENCE';Ledger.G4_RESULT_COUNT=1;Ledger.AcceptedPackageSHA256=char(string(pkg));
elseif Action=="QUARANTINE"
    assert(state=="GENERATED_UNACCEPTED",'G4Seed1DSAL:InvalidTransition','Quarantine requires GENERATED_UNACCEPTED.');
    assert(strcmp(string(Ledger.ScientificRunId),string(runId)),'G4Seed1DSAL:RunIdentityMismatch','Ledger run id mismatch.');
    Ledger.State='QUARANTINED_HOLD';Ledger.G4_RESULT_COUNT=0;
else
    error('G4Seed1DSAL:UnknownAction','Unknown ledger action.');
end
entry=struct('From',char(state),'To',Ledger.State,'ScientificRunId',char(string(runId)), ...
    'UTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSSXXX')),'Action',char(Action));
if ~isfield(Ledger,'TransitionHistory')||isempty(Ledger.TransitionHistory),Ledger.TransitionHistory=entry;else,Ledger.TransitionHistory(end+1)=entry;end
Ledger.LastTransitionUTC=entry.UTC;
atomicWriteJsonLocal(LedgerPath,Ledger);NewSHA256=sha256FileLocal(LedgerPath);
end
function value=requiredContextLocal(S,name)
assert(isfield(S,name),'G4Seed1DSAL:ContextMissing','Ledger context missing %s.',name);value=S.(name);
end
function atomicWriteJsonLocal(path,S)
folder=fileparts(path);tmp=fullfile(folder,".ledger_"+string(char(java.util.UUID.randomUUID()))+".tmp");
fid=fopen(tmp,'w','n','UTF-8');assert(fid>0,'G4Seed1DSAL:WriteFailed');
try
    fwrite(fid,jsonencode(S,'PrettyPrint',true),'char');
    fclose(fid);
catch ME
    try,fclose(fid);catch,end
    rethrow(ME);
end
[ok,msg]=movefile(tmp,path,'f');assert(ok,'G4Seed1DSAL:AtomicCommitFailed','%s',msg);
end
function h=sha256FileLocal(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
