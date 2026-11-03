function [Manifest,Report]=PersistG4Seed1GeneratedObjects_v1(Science,PreRARC,PostRARC,OutputRoot)
% Stage exactly 12 GENERATED_UNACCEPTED object classes and hash every object.
arguments
    Science (1,1) struct
    PreRARC (1,1) struct
    PostRARC (1,1) struct
    OutputRoot (1,1) string
end
assert(~isfolder(OutputRoot),'G4Seed1Retention:OutputExists','Fresh run staging directory already exists.');mkdir(OutputRoot);
R=Science.RunIdentity;paths=strings(12,1);classes=["SeedIdentity";"EventFacts";"RawHTotal";"RawHPositiveNegativeAxis"; ...
    "ObservedResponses";"ReconstructedM0C";"ScalarQoITable";"SideMetrics";"NormalizedEnvelopeVectors";"v_model";"GateLog";"RuntimePathSHAProvenance"];
paths(1)=fullfile(OutputRoot,'01_SeedIdentity.json');writeJsonLocal(paths(1),R);
paths(2)=fullfile(OutputRoot,'02_EventFacts.mat');M2Events=Science.Pair.M2Events;save(paths(2),'M2Events','-v7.3');
paths(3)=fullfile(OutputRoot,'03_RawHTotal.mat');RawHTotal=Science.RawResponses.hTotal;save(paths(3),'RawHTotal','-v7.3');
paths(4)=fullfile(OutputRoot,'04_RawHPositiveNegativeAxis.mat');RawSides=Science.RawResponses;save(paths(4),'RawSides','-v7.3');
paths(5)=fullfile(OutputRoot,'05_ObservedResponses.mat');ObservedResponses=Science.ObservedResponses;save(paths(5),'ObservedResponses','-v7.3');
paths(6)=fullfile(OutputRoot,'06_ReconstructedM0C.mat');M0CEvents=Science.Pair.M0CEvents;M0Ch=Science.Pair.M0ChSca;save(paths(6),'M0CEvents','M0Ch','-v7.3');
paths(7)=fullfile(OutputRoot,'07_ScalarQoITable.csv');writetable(Science.D1MCTOutputs,paths(7));
paths(8)=fullfile(OutputRoot,'08_SideMetrics.json');writeJsonLocal(paths(8),Science.SideMetricOutputs);
paths(9)=fullfile(OutputRoot,'09_NormalizedEnvelopeVectors.mat');NormalizedM0C=Science.EnvelopeOutputs.NormalizedM0C;NormalizedM2=Science.EnvelopeOutputs.NormalizedM2;save(paths(9),'NormalizedM0C','NormalizedM2','-v7.3');
paths(10)=fullfile(OutputRoot,'10_v_model.mat');v_model=Science.EnvelopeOutputs.v_model;save(paths(10),'v_model','-v7.3');
paths(11)=fullfile(OutputRoot,'11_GateLog.json');writeJsonLocal(paths(11),struct('State',"GENERATED_UNACCEPTED",'EvidenceBuilder',"PENDING_INTERNAL_EXECUTION",'ScientificRunId',R.ScientificRunId));
paths(12)=fullfile(OutputRoot,'12_RuntimePathSHAProvenance.json');writeJsonLocal(paths(12),struct('PRE',PreRARC,'POST',PostRARC));
n=12;objectId="OBJ"+compose('%02d',(1:n)');bytes=zeros(n,1);sha=strings(n,1);runId=repmat(string(R.ScientificRunId),n,1);idx=ones(n,1);seed=repmat(double(R.Seed),n,1);payload=repmat(string(R.PayloadSHA256),n,1);rmv=repmat(double(R.RandomModelVersion),n,1);utc=repmat(string(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSSXXX')),n,1);state=repmat("GENERATED_UNACCEPTED",n,1);
for k=1:n,d=dir(paths(k));bytes(k)=d.bytes;sha(k)=sha256FileLocal(paths(k));end
Manifest=table(classes,objectId,paths,bytes,sha,runId,idx,seed,payload,rmv,utc,state,'VariableNames', ...
    {'ObjectClass','ObjectId','ObjectPath','ObjectBytes','ObjectSHA256','ScientificRunId','RosterIndex','Seed','PayloadSHA256','RandomModelVersion','CreationUTC','AcceptanceState'});
writetable(Manifest,fullfile(OutputRoot,'RetentionManifest.csv'));
Report=ValidateG4Seed1RetentionManifest_v1(Manifest,R);assert(Report.AllPass,'G4Seed1Retention:Incomplete','Retention manifest incomplete.');
end
function writeJsonLocal(path,S),fid=fopen(path,'w','n','UTF-8');assert(fid>0);fwrite(fid,jsonencode(S,'PrettyPrint',true),'char');fclose(fid);end
function h=sha256FileLocal(path),fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[])));end %#ok<NASGU>
