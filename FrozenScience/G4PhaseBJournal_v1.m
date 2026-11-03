function Receipt=G4PhaseBJournal_v1(Root,Identity,Stage,Counts,Artifacts)
% 每条 journal 记录单独原子提交；前序 SHA 链，禁止覆盖/跳阶段。
arguments
    Root (1,1) string
    Identity (1,1) struct
    Stage (1,1) string
    Counts (1,1) struct
    Artifacts = struct([])
end
folder=fullfile(Root,'AttemptJournal');if ~isfolder(folder),mkdir(folder);end
files=dir(fullfile(folder,'*.json'));[~,ix]=sort({files.name});files=files(ix);
previous="";previousStage="";
for k=1:numel(files)
    p=string(fullfile(files(k).folder,files(k).name));j=jsondecode(fileread(p));
    assert(j.Sequence==k && string(j.PreviousSHA256)==previous,'G4PB:JournalChain','G4PB:JournalChain');
    assert(string(j.Identity.ScientificRunId)==string(Identity.ScientificRunId),'G4PB:JournalOwner','G4PB:JournalOwner');
    previous=G4PhaseBIO_v1("HASH",p);previousStage=string(j.Stage);
end
order=["PREPARED","TRAVERSAL_ENTERED","TRAVERSAL_RETURNED","RAW_CAPTURE_COMMITTED","PAIRING_EVALUATED","PHASE_B_SEALED"];
if Stage=="PHASE_B_SEALED"
    assert(any(previousStage==order(1:5)),'G4PB:JournalOrder','G4PB:JournalOrder');
else
    n=find(order==Stage);assert(~isempty(n) && numel(files)==n-1,'G4PB:JournalOrder','G4PB:JournalOrder');
end
record=struct('Sequence',numel(files)+1,'PreviousSHA256',char(previous),'Stage',char(Stage), ...
    'Identity',Identity,'UTC',char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSSXXX")), ...
    'Counts',Counts,'Artifacts',Artifacts);
Receipt=G4PhaseBIO_v1("JSON",fullfile(folder,sprintf('%02d_%s.json',numel(files)+1,Stage)),record);
end
