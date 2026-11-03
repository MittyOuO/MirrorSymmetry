function LineageEnvelope=MergeG4CanonicalPairingRuns_v2_2(InputEnvelopes,OutputRoot)
%MergeG4CanonicalPairingRuns_v2_2 Exact external merge with SHA-bound lineage.
arguments
    InputEnvelopes (:,1) struct
    OutputRoot (1,1) string
end
assert(~isempty(InputEnvelopes),'G4GCPCv22:MissingRun','At least one input envelope is required.');
if ~isfolder(OutputRoot),mkdir(OutputRoot);end
baseInputs=InputEnvelopes;current=repmat(emptyEnvelopeLocal(),numel(baseInputs),1);allGenerated=repmat(emptyEnvelopeLocal(),0,1);stage=0;timer=tic;
baseManifestSHA=strings(numel(InputEnvelopes),1);baseRunSHA=strings(numel(InputEnvelopes),1);
for k=1:numel(baseInputs)
    m=verifyEnvelopeLocal(baseInputs(k));baseManifestSHA(k)=string(baseInputs(k).ManifestSHA256);baseRunSHA(k)=string(m.RunSHA256);
    current(k)=commonEnvelopeLocal(baseInputs(k),m);
end
while numel(current)>1
    stage=stage+1;next=repmat(emptyEnvelopeLocal(),ceil(numel(current)/2),1);q=0;
    for k=1:2:numel(current)
        q=q+1;
        if k==numel(current)
            next(q)=current(k);
        else
            left=verifyEnvelopeLocal(current(k));right=verifyEnvelopeLocal(current(k+1));
            outputPath=fullfile(OutputRoot,sprintf('merge_stage%02d_batch%04d.run',stage,q));
            mergeTwoLocal(string(left.RunPath),string(right.RunPath),outputPath);
            info=dir(outputPath);outputSHA=hashLocal(outputPath);
            manifest=struct('ManifestVersion','G4_GCPC_MERGE_RUN_MANIFEST_v2_2', ...
                'MergeStage',stage,'MergeBatchId',q, ...
                'OrderedInputRunSHA256',[string(left.RunSHA256);string(right.RunSHA256)], ...
                'OrderedInputManifestSHA256',[string(current(k).ManifestSHA256);string(current(k+1).ManifestSHA256)], ...
                'OutputRunPath',char(outputPath),'RunPath',char(outputPath), ...
                'OutputRunBytes',info.bytes,'RunBytes',info.bytes, ...
                'OutputRunSHA256',outputSHA,'RunSHA256',outputSHA, ...
                'OutputRecordCount',double(left.RecordCount)+double(right.RecordCount), ...
                'RecordCount',double(left.RecordCount)+double(right.RecordCount), ...
                'RecordSchemaVersion','G4_GCPC_EXACT_TSV_HEX_v2_2', ...
                'CanonicalTupleVersion','G4_COMMON_EVENT_TUPLE_v1');
            manifestPath=outputPath+".merge-manifest.json";writeJsonLocal(manifestPath,manifest);
            next(q)=struct('EnvelopeVersion','G4_GCPC_MERGE_MANIFEST_ENVELOPE_v2_2', ...
                'ManifestPath',char(manifestPath),'ManifestSHA256',hashLocal(manifestPath), ...
                'RunPath',char(outputPath),'RunSHA256',outputSHA,'RecordCount',manifest.RecordCount);
            allGenerated(end+1,1)=next(q); %#ok<AGROW>
        end
    end
    current=next;
end
final=verifyEnvelopeLocal(current(1));
lineage=struct('LineageVersion','G4_GCPC_GLOBAL_MERGE_LINEAGE_v2_2', ...
    'BaseInputCount',numel(InputEnvelopes),'OrderedBaseRunSHA256',baseRunSHA, ...
    'OrderedBaseRunManifestSHA256',baseManifestSHA, ...
    'GeneratedMergeManifestPaths',string({allGenerated.ManifestPath}).', ...
    'GeneratedMergeManifestSHA256',string({allGenerated.ManifestSHA256}).', ...
    'MergeStageCount',stage,'FinalRunPath',char(final.RunPath), ...
    'FinalRunBytes',double(final.RunBytes),'FinalRunSHA256',char(string(final.RunSHA256)), ...
    'FinalRunRecordCount',double(final.RecordCount), ...
    'FinalRunManifestPath',char(current(1).ManifestPath), ...
    'FinalRunManifestSHA256',char(current(1).ManifestSHA256), ...
    'WallSeconds',toc(timer),'Algorithm','PAIRWISE_HIERARCHICAL_EXACT_LEXICOGRAPHIC_MERGE', ...
    'HashUsedAsSoleEqualityAuthority',false);
lineagePath=fullfile(OutputRoot,'GCPC_GlobalMergeLineage_v2_2.json');writeJsonLocal(lineagePath,lineage);
LineageEnvelope=struct('EnvelopeVersion','G4_GCPC_GLOBAL_MERGE_LINEAGE_ENVELOPE_v2_2', ...
    'LineageManifestPath',char(lineagePath),'LineageManifestSHA256',hashLocal(lineagePath), ...
    'FinalRunPath',char(final.RunPath),'FinalRunSHA256',char(string(final.RunSHA256)), ...
    'FinalRunManifestPath',char(current(1).ManifestPath), ...
    'FinalRunManifestSHA256',char(current(1).ManifestSHA256), ...
    'FinalRunRecordCount',double(final.RecordCount),'MergeStageCount',stage,'MergeWallSeconds',lineage.WallSeconds);
end

function m=verifyEnvelopeLocal(e)
assert(isfield(e,'ManifestPath')&&isfield(e,'ManifestSHA256'),'G4GCPCv22:ManifestEnvelope','Manifest envelope is incomplete.');
assert(isfile(e.ManifestPath),'G4GCPCv22:RunManifestMissing','Run manifest is missing.');
assert(strcmp(hashLocal(e.ManifestPath),char(string(e.ManifestSHA256))),'G4GCPCv22:RunManifestSHAMismatch','Run manifest SHA mismatch.');
m=jsondecode(fileread(e.ManifestPath));
assert(isfield(m,'RunPath')&&isfield(m,'RunBytes')&&isfield(m,'RunSHA256')&&isfield(m,'RecordCount'), ...
    'G4GCPCv22:RunManifestSchema','Run manifest schema is incomplete.');
assert(isfile(m.RunPath),'G4GCPCv22:RunMissing','Registered run is missing.');info=dir(m.RunPath);
assert(info.bytes==double(m.RunBytes),'G4GCPCv22:RunBytesMismatch','Registered run bytes mismatch.');
assert(strcmp(hashLocal(m.RunPath),m.RunSHA256),'G4GCPCv22:RunSHAMismatch','Registered run SHA mismatch.');
assert(strcmp(m.RecordSchemaVersion,'G4_GCPC_EXACT_TSV_HEX_v2_2')&& ...
    strcmp(m.CanonicalTupleVersion,'G4_COMMON_EVENT_TUPLE_v1'),'G4GCPCv22:RunSchemaMismatch','Run schema/tuple version mismatch.');
if isfield(m,'SourceChunkManifestPath')
    assert(isfile(m.SourceChunkManifestPath),'G4GCPCv22:SourceManifestMissing','Source chunk manifest is missing.');
    assert(strcmp(hashLocal(m.SourceChunkManifestPath),m.SourceChunkManifestSHA256), ...
        'G4GCPCv22:SourceManifestSHAMismatch','Source chunk manifest SHA mismatch.');
end
end
function mergeTwoLocal(pathA,pathB,outPath)
fa=fopen(pathA,'r','n','UTF-8');assert(fa>=0,'G4GCPCv22:RunOpen','Cannot open %s.',pathA);ca=onCleanup(@()fclose(fa)); %#ok<NASGU>
fb=fopen(pathB,'r','n','UTF-8');assert(fb>=0,'G4GCPCv22:RunOpen','Cannot open %s.',pathB);cb=onCleanup(@()fclose(fb)); %#ok<NASGU>
fo=fopen(outPath,'w','n','UTF-8');assert(fo>=0,'G4GCPCv22:RunWrite','Cannot write %s.',outPath);co=onCleanup(@()fclose(fo)); %#ok<NASGU>
a=nextLineLocal(fa);b=nextLineLocal(fb);
while ~isempty(a)||~isempty(b)
    if isempty(b)||(~isempty(a)&&lexCompareLocal(a,b)<=0),fprintf(fo,'%s\n',a);a=nextLineLocal(fa);
    else,fprintf(fo,'%s\n',b);b=nextLineLocal(fb);end
end
end
function line=nextLineLocal(fid),line=fgetl(fid);if ~ischar(line),line='';end,end
function cmp=lexCompareLocal(a,b)
aa=unicode2native(a,'UTF-8');bb=unicode2native(b,'UTF-8');n=min(numel(aa),numel(bb));q=find(aa(1:n)~=bb(1:n),1);
if isempty(q),cmp=sign(numel(aa)-numel(bb));else,cmp=sign(double(aa(q))-double(bb(q)));end
end
function e=emptyEnvelopeLocal()
e=struct('EnvelopeVersion','','ManifestPath','','ManifestSHA256','','RunPath','','RunSHA256','','RecordCount',0);
end
function e=commonEnvelopeLocal(input,m)
e=emptyEnvelopeLocal();e.EnvelopeVersion=char(string(input.EnvelopeVersion));e.ManifestPath=char(string(input.ManifestPath));
e.ManifestSHA256=char(string(input.ManifestSHA256));e.RunPath=char(string(m.RunPath));e.RunSHA256=char(string(m.RunSHA256));e.RecordCount=double(m.RecordCount);
end
function sha=hashLocal(path)
md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'r');assert(fid>=0,'G4GCPCv22:HashOpen','Cannot hash %s.',path);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true,d=fread(fid,1024*1024,'*uint8');if isempty(d),break;end;md.update(typecast(d,'int8'));end
sha=char(lower(reshape(dec2hex(mod(double(md.digest()),256),2).',1,[])));
end
function writeJsonLocal(file,value)
fid=fopen(file,'w');assert(fid>=0,'G4GCPCv22:Write','Cannot write %s.',file);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true));
end
