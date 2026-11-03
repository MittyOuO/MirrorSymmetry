function Token=G4ExclusiveTraversalLock_v1(Action,LockPath,Identity,Token,Outcome)
% Windows 本机排他锁。无自动超时/清理；崩溃后保留锁，必须走 RRB。
arguments
    Action (1,1) string
    LockPath (1,1) string
    Identity (1,1) struct
    Token = struct()
    Outcome = struct()
end
switch Action
    case "ACQUIRE"
        required={'ScientificRunId','RosterIndex','Seed','AuthorizationArtifactSHA256', ...
            'ScienceRunnerSHA256','ContractSHA256','PID','Host','CreatedUTC','DSALPath'};
        for k=1:numel(required),assert(isfield(Identity,required{k}),'G4ETL:MissingIdentity','G4ETL:MissingIdentity');end
        assert(Identity.RosterIndex==1 && Identity.Seed==262709171,'G4ETL:IdentityMismatch','G4ETL:IdentityMismatch');
        folder=fileparts(LockPath);if ~isfolder(folder),mkdir(folder);end
        content=Identity;content.LockVersion='G4_ETL_v1';content.OwnerNonce=char(java.util.UUID.randomUUID());
        bytes=unicode2native(jsonencode(content,'PrettyPrint',true),'UTF-8');
        try
            stream=System.IO.FileStream(char(LockPath),System.IO.FileMode.CreateNew,System.IO.FileAccess.ReadWrite,System.IO.FileShare.Read);
        catch ME
            error('G4ETL:LockedOrUnavailable','Lock acquisition denied: %s',ME.message);
        end
        try
            stream.Write(bytes,0,numel(bytes));stream.Flush(true);
            readback=jsondecode(fileread(LockPath));
            assert(isequaln(readback,content),'G4ETL:ReadbackMismatch','G4ETL:ReadbackMismatch');
            Token=struct('Path',LockPath,'Identity',content,'Stream',stream,'SHA256',G4PhaseBIO_v1("HASH",LockPath));
        catch ME
            stream.Dispose(); % 不删除文件：不完整锁也 fail closed。
            rethrow(ME);
        end
    case "VERIFY"
        assert(string(Token.Path)==LockPath && isfile(LockPath),'G4ETL:NotOwner','G4ETL:NotOwner');
        current=jsondecode(fileread(LockPath));
        assert(isequaln(current,Token.Identity) && string(current.ScientificRunId)==string(Identity.ScientificRunId) ...
            && current.PID==feature('getpid') && string(current.Host)==string(System.Environment.MachineName), ...
            'G4ETL:NotOwner','Caller does not own the lock.');
        assert(G4PhaseBIO_v1("HASH",LockPath)==Token.SHA256 && Token.Stream.CanWrite,'G4ETL:NotOwner','G4ETL:NotOwner');
    case "RELEASE"
        G4ExclusiveTraversalLock_v1("VERIFY",LockPath,Identity,Token);
        G4PhaseBIO_v1("VERIFY","",Outcome);
        sealed=jsondecode(fileread(Outcome.Path));
        assert(string(sealed.Identity.ScientificRunId)==string(Identity.ScientificRunId),'G4ETL:OutcomeOwner','Outcome run ID differs.');
        assert(any(string(sealed.Outcome)==["PASS_GENERATED_UNACCEPTED","QUARANTINED_HOLD","HOLD_BEFORE_TRAVERSAL"]), ...
            'G4ETL:OutcomeNotDurable','Outcome does not permit release.');
        assert(string(sealed.Stage)=="PHASE_B_SEALED" && ~isempty(sealed.Artifacts),'G4ETL:OutcomeNotDurable','G4ETL:OutcomeNotDurable');
        for k=1:numel(sealed.Artifacts),G4PhaseBIO_v1("VERIFY","",sealed.Artifacts(k));end
        journalFound=false;
        for k=1:numel(sealed.Artifacts)
            if contains(string(sealed.Artifacts(k).Path),"PHASE_B_SEALED.json")
                journal=jsondecode(fileread(sealed.Artifacts(k).Path));
                journalFound=string(journal.Stage)=="PHASE_B_SEALED" && ...
                    string(journal.Identity.ScientificRunId)==string(Identity.ScientificRunId);
            end
        end
        assert(journalFound,'G4ETL:OutcomeNotDurable','G4ETL:OutcomeNotDurable');
        % 释放到删除间文件仍存在，其他 CreateNew 不可能抢占成功。
        Token.Stream.Dispose();System.IO.File.Delete(char(LockPath));
        Token.Released=true;
    otherwise
        error('G4ETL:UnknownAction','Unknown lock action.');
end
end
