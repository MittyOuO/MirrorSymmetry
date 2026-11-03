function Receipt=SealG4PhaseBAttempt_v1(Context,Passed,Failure)
% 仅终结本次尝试；不接受科学结果、不重跑、不删除未闭合的锁。
arguments
    Context (1,1) struct
    Passed (1,1) logical
    Failure = struct('Identifier','','Message','','Stack',[])
end
root=string(Context.Root);capsulePath=fullfile(root,'RawCaptureManifest.json');
entered=isfile(fullfile(root,'AttemptJournal','02_TRAVERSAL_ENTERED.json'));
counts=struct('M2TraversalCount',double(entered),'RandomDrawCount',[],'RandomDrawStatus','UNKNOWN');
if isfile(capsulePath)
    capsule=jsondecode(fileread(capsulePath));
    assert(string(capsule.Identity.ScientificRunId)==string(Context.Identity.ScientificRunId),'G4PB:CapsuleIdentity','G4PB:CapsuleIdentity');
    for k=1:numel(capsule.Artifacts),G4PhaseBIO_v1("VERIFY","",capsule.Artifacts(k));end
    ledger=jsondecode(fileread(Context.Identity.DSALPath));
    if string(ledger.State)=="NOT_RUN"
        UpdateG4Seed1AcceptanceLedger_v1(Context.Identity.DSALPath,Context.LedgerSHA256,"MARK_GENERATED",Context.Identity);
    end
    ledger=jsondecode(fileread(Context.Identity.DSALPath));
    assert(string(ledger.ScientificRunId)==string(Context.Identity.ScientificRunId),'G4PB:LedgerIdentity','G4PB:LedgerIdentity');
    if Passed
        assert(string(ledger.State)=="GENERATED_UNACCEPTED",'G4PB:LedgerState','G4PB:LedgerState');
        v=jsondecode(fileread(fullfile(root,'PairingVerdict.json')));assert(v.PASS,'G4PB:PairingNotPassed','G4PB:PairingNotPassed');
        outcome='PASS_GENERATED_UNACCEPTED';
    else
        if string(ledger.State)=="GENERATED_UNACCEPTED"
            UpdateG4Seed1AcceptanceLedger_v1(Context.Identity.DSALPath,G4PhaseBIO_v1("HASH",Context.Identity.DSALPath),"QUARANTINE",Context.Identity);
        end
        outcome='QUARANTINED_HOLD';
    end
elseif entered
    % 进入之后未完成 capsule：不能假称 forensic closure，保留锁。
    G4PhaseBIO_v1("JSON",fullfile(root,'UnsealedFailure.json'), ...
        struct('Identity',Context.Identity,'Outcome','HOLD_UNRESOLVED_RAW_CAPTURE','Failure',Failure));
    error('G4PB:UnresolvedRawCapture','Raw capture not closed; stale lock retained. No retry authorized.');
else
    assert(~Passed,'G4PB:PassWithoutTraversal','G4PB:PassWithoutTraversal');outcome='HOLD_BEFORE_TRAVERSAL';
end
identityPath=fullfile(root,'ReturnedRandomIdentity.json');
if isfile(identityPath),x=jsondecode(fileread(identityPath));counts=x.Counts;end
G4PhaseBIO_v1("JSON",fullfile(root,'AttemptOutcome.json'),struct('Identity',Context.Identity, ...
    'Outcome',outcome,'Failure',Failure,'Counts',counts,'G4_RESULT_COUNT',0,'G5','LOCKED'));
ledgerSnapshot=jsondecode(fileread(Context.Identity.DSALPath));
G4PhaseBIO_v1("JSON",fullfile(root,'DSAL_Snapshot.json'),ledgerSnapshot);
% live lock/DSAL 不是不可变证据，用快照代替；不收集临时工作目录。
G4PhaseBIO_v1("JSON",fullfile(root,'LockOwnershipSnapshot.json'),Context.LockToken.Identity);
files=[dir(fullfile(root,'*'));dir(fullfile(root,'AttemptJournal','*.json'))];
artifacts=struct('Path',{},'SHA256',{},'Bytes',{});
for k=1:numel(files)
    if files(k).isdir || endsWith(files(k).name,'.pending'),continue;end
    p=string(fullfile(files(k).folder,files(k).name));
    if strcmpi(p,string(Context.LockPath)) || strcmpi(p,string(Context.Identity.DSALPath)),continue;end
    artifacts(end+1)=struct('Path',char(p),'SHA256',char(G4PhaseBIO_v1("HASH",p)),'Bytes',files(k).bytes); %#ok<AGROW>
end
j=G4PhaseBJournal_v1(root,Context.Identity,"PHASE_B_SEALED",counts,artifacts);
receiptData=struct('Identity',Context.Identity,'Stage','PHASE_B_SEALED','Outcome',outcome, ...
    'Artifacts',[artifacts j],'LedgerSHA256',char(G4PhaseBIO_v1("HASH",Context.Identity.DSALPath)), ...
    'G4_RESULT_COUNT',0,'Seed2To20','NOT_AUTHORIZED','G5','LOCKED');
Receipt=G4PhaseBIO_v1("JSON",fullfile(root,'DurableOutcomeReceipt.json'),receiptData);
end
