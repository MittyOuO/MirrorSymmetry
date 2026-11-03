function R=G4PhaseBIO_v1(Action,Path,Data)
% Phase B 不可覆盖提交：同目录临时文件、Flush(true)、SHA、原子改名。
arguments
    Action (1,1) string
    Path (1,1) string
    Data = []
end
switch Action
    case "HASH"
        s=System.IO.File.Open(char(Path),System.IO.FileMode.Open,System.IO.FileAccess.Read,System.IO.FileShare.ReadWrite);
        c=onCleanup(@()s.Dispose());
        algorithm=System.Security.Cryptography.SHA256.Create();
        b=uint8(algorithm.ComputeHash(s));algorithm.Dispose();
        R=string(lower(reshape(dec2hex(b,2).',1,[])));
    case "VERIFY"
        assert(isfile(Data.Path),'G4PB:ArtifactMissing','G4PB:ArtifactMissing');
        info=dir(Data.Path);
        assert(info.bytes==Data.Bytes && G4PhaseBIO_v1("HASH",string(Data.Path))==string(Data.SHA256), ...
            'G4PB:ArtifactChanged','Artifact bytes or SHA changed.');
        R=true;
    case {"JSON","MAT"}
        assert(~isfile(Path),'G4PB:OverwriteProhibited','G4PB:OverwriteProhibited');
        folder=fileparts(Path);if ~isfolder(folder),mkdir(folder);end
        tmp=Path+"."+string(char(java.util.UUID.randomUUID()))+".pending";
        % 失败时保留 pending，禁止把部分文件作为已提交证据。
        if Action=="MAT"
            save(char(tmp),'-struct','Data','-v7.3');
        else
            bytes=unicode2native(jsonencode(Data,'PrettyPrint',true),'UTF-8');
            f=System.IO.FileStream(char(tmp),System.IO.FileMode.CreateNew,System.IO.FileAccess.Write,System.IO.FileShare.None);
            try
                f.Write(bytes,0,numel(bytes));f.Flush(true);f.Dispose();
            catch ME
                f.Dispose();rethrow(ME);
            end
        end
        f=System.IO.File.Open(char(tmp),System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
        f.Flush(true);f.Dispose();
        h=G4PhaseBIO_v1("HASH",tmp);info=dir(tmp);
        System.IO.File.Move(char(tmp),char(Path)); % 不覆盖，单卷 rename
        R=struct('Path',char(Path),'SHA256',char(h),'Bytes',info.bytes);
        G4PhaseBIO_v1("VERIFY","",R);
    otherwise
        error('G4PB:UnknownIOAction','Unknown IO action.');
end
end
