function Token=G4Seed1RecoveryLock_v1(Action,LockPath,Identity,Token,OutcomeReceipt)
%G4Seed1RecoveryLock_v1 Durable lock for authorized deterministic recovery.
% The production RecoveryLock is NOT acquired by this preparation task.
arguments
    Action (1,1) string {mustBeMember(Action,["ACQUIRE","VERIFY","RELEASE"])}
    LockPath (1,1) string
    Identity (1,1) struct
    Token = struct()
    OutcomeReceipt = struct()
end
required={'ScientificRunId','RecoveryExecutionId','ParentCheckpoint', ...
    'SourceEventFactsSHA256','StaleETLSupersessionRecordSHA256','AuthorizationSHA256', ...
    'PID','Host','CreatedUTC'};
for k=1:numel(required),assert(isfield(Identity,required{k}),'G4CRLock:MissingIdentity','Missing recovery identity %s.',required{k});end
assert(string(Identity.ScientificRunId)=="43b3b9d6-cb24-4ede-9bee-f53e47b505c4", ...
    'G4CRLock:ScientificRunId','Recovery must preserve the original ScientificRunId.');
assert(string(Identity.ParentCheckpoint)=="RAW_CAPTURE_COMMITTED", ...
    'G4CRLock:Checkpoint','Recovery may start only from RAW_CAPTURE_COMMITTED.');
assert(string(Identity.SourceEventFactsSHA256)=="e580ffb394b60fa983a4ec27f0d05645b77dc7691a938b8e52309a8515b98494", ...
    'G4CRLock:SourceEventFactsSHA','RecoveryLock source facts SHA is not the committed Seed-1 authority.');
assert(strlength(string(Identity.AuthorizationSHA256))==64&& ...
    ~contains(string(Identity.AuthorizationSHA256),"NOT_ISSUED",'IgnoreCase',true), ...
    'G4CRLock:Authorization','RecoveryLock requires a future issued 64-hex authorization SHA.');
switch Action
    case "ACQUIRE"
        folder=fileparts(LockPath);if ~isfolder(folder),mkdir(folder);end
        content=Identity;content.LockVersion='G4_SEED1_COMPACT_RECOVERY_LOCK_v1';
        content.RecoveryMode='DETERMINISTIC_POSTPROCESSING_ONLY';
        content.M2TraversalCountDuringRecoveryExpected=0;
        content.RandomDrawCountDuringRecoveryExpected=0;
        content.OwnerNonce=char(java.util.UUID.randomUUID());
        bytes=unicode2native(jsonencode(content,'PrettyPrint',true),'UTF-8');
        try
            stream=System.IO.FileStream(char(LockPath),System.IO.FileMode.CreateNew, ...
                System.IO.FileAccess.ReadWrite,System.IO.FileShare.Read);
        catch ME
            error('G4CRLock:LockedOrUnavailable','RecoveryLock acquisition denied: %s',ME.message);
        end
        try
            stream.Write(bytes,0,numel(bytes));stream.Flush(true);
            readback=jsondecode(fileread(LockPath));
            assert(isequaln(readback,content),'G4CRLock:Readback','RecoveryLock readback mismatch.');
            Token=struct('Path',LockPath,'Identity',content,'Stream',stream, ...
                'SHA256',hashLocal(LockPath),'Released',false);
        catch ME
            stream.Dispose();rethrow(ME);
        end
    case "VERIFY"
        assert(isfile(LockPath)&&isfield(Token,'Stream')&&Token.Stream.CanWrite, ...
            'G4CRLock:NotOwner','RecoveryLock token is not live.');
        current=jsondecode(fileread(LockPath));
        assert(isequaln(current,Token.Identity)&&string(Token.Path)==LockPath&& ...
            current.PID==feature('getpid')&&string(current.Host)==string(System.Environment.MachineName)&& ...
            hashLocal(LockPath)==string(Token.SHA256), ...
            'G4CRLock:NotOwner','Caller does not own the exact RecoveryLock.');
    case "RELEASE"
        G4Seed1RecoveryLock_v1("VERIFY",LockPath,Identity,Token);
        assert(isfield(OutcomeReceipt,'Path')&&isfield(OutcomeReceipt,'SHA256')&&isfile(OutcomeReceipt.Path), ...
            'G4CRLock:OutcomeNotDurable','Durable recovery outcome receipt is required.');
        assert(hashLocal(OutcomeReceipt.Path)==string(OutcomeReceipt.SHA256), ...
            'G4CRLock:OutcomeNotDurable','Outcome receipt SHA mismatch.');
        sealed=jsondecode(fileread(OutcomeReceipt.Path));
        assert(isfield(sealed,'ScientificRunId')&&string(sealed.ScientificRunId)==string(Identity.ScientificRunId)&& ...
            isfield(sealed,'RecoveryExecutionId')&&string(sealed.RecoveryExecutionId)==string(Identity.RecoveryExecutionId)&& ...
            isfield(sealed,'Stage')&&string(sealed.Stage)=="RECOVERY_SEALED"&& ...
            isfield(sealed,'M2TraversalCountDuringRecovery')&&sealed.M2TraversalCountDuringRecovery==0&& ...
            isfield(sealed,'RandomDrawCountDuringRecovery')&&sealed.RandomDrawCountDuringRecovery==0, ...
            'G4CRLock:OutcomeNotDurable','Outcome receipt does not authorize lock release.');
        Token.Stream.Dispose();System.IO.File.Delete(char(LockPath));Token.Released=true;
end
end

function sha=hashLocal(path)
md=java.security.MessageDigest.getInstance('SHA-256');
fid=fopen(path,'r');assert(fid>=0,'G4CRLock:HashOpen','Cannot hash %s.',path);cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true,data=fread(fid,1024*1024,'*uint8');if isempty(data),break;end;md.update(typecast(data,'int8'));end
sha=string(lower(reshape(dec2hex(mod(double(md.digest()),256),2).',1,[])));
end
