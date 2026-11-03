function Envelope=ExtractG4CanonicalPairingRuns_v2_2(Events,SourceIndices,ChunkId,RunPath,ActualMap,SourceEventFactsSHA256)
%ExtractG4CanonicalPairingRuns_v2_2 Exact expected/actual records with durable manifests.
arguments
    Events (:,1) struct
    SourceIndices (:,1) uint64
    ChunkId (1,1) uint32
    RunPath (1,1) string
    ActualMap (1,1) struct
    SourceEventFactsSHA256 (1,1) string
end
assert(numel(Events)==numel(SourceIndices)&&~isempty(Events),'G4GCPCv22:ChunkShape', ...
    'Events and SourceIndices must be nonempty and one-to-one.');
assert(all(diff(double(SourceIndices))==1),'G4GCPCv22:ChunkRange','SourceIndices must be contiguous.');
assert(isfield(ActualMap,'PlusSourceIndices')&&isfield(ActualMap,'AxisSourceIndices')&& ...
    isfield(ActualMap,'MapAuthorityVersion'),'G4GCPCv22:ActualMapSchema','ActualMap schema is incomplete.');

tuples=CanonicalG4CommonEventTuple_v2(Events);y=reshape(double([Events.Y]),[],1);
expectedPlus=SourceIndices(y>0);expectedAxis=SourceIndices(y==0);
expectedRelevant=[expectedPlus;expectedAxis];expectedSides=[repmat("PLUS",numel(expectedPlus),1);repmat("AXIS",numel(expectedAxis),1)];
[expectedRelevant,order]=sort(expectedRelevant);expectedSides=expectedSides(order);

actualPlus=uint64(ActualMap.PlusSourceIndices(:));actualAxis=uint64(ActualMap.AxisSourceIndices(:));
lineCount=numel(expectedRelevant)+numel(actualPlus)+numel(actualAxis);lines=strings(lineCount,1);record=0;tab=string(sprintf('\t'));
for k=1:numel(expectedRelevant)
    local=find(SourceIndices==expectedRelevant(k),1);record=record+1;
    lines(record)=utf8HexLocal(tuples(local))+tab+expectedSides(k)+"_EXPECTED"+tab+string(expectedRelevant(k))+tab+string(ChunkId);
end
[lines,record]=appendActualLocal(lines,record,actualPlus,"PLUS_ACTUAL",SourceIndices,tuples,ChunkId,tab);
[lines,record]=appendActualLocal(lines,record,actualAxis,"AXIS_ACTUAL",SourceIndices,tuples,ChunkId,tab);
assert(record==lineCount,'G4GCPCv22:RecordCount','Internal record count mismatch.');
lines=sort(lines,'ascend');folder=fileparts(RunPath);if ~isfolder(folder),mkdir(folder);end
writelines(lines,RunPath,'Encoding','UTF-8');

domainPath=RunPath+".source-domain.tsv";domainLines=string(expectedRelevant)+tab+expectedSides;
writelines(domainLines,domainPath,'Encoding','UTF-8');domainInfo=dir(domainPath);
sourceManifest=struct('ManifestVersion','G4_GCPC_SOURCE_CHUNK_MANIFEST_v2_2', ...
    'ChunkId',double(ChunkId),'ChunkStartIndex',double(SourceIndices(1)), ...
    'ChunkEndIndex',double(SourceIndices(end)),'ChunkSourceEventCount',numel(SourceIndices), ...
    'RelevantSourceEventCount',numel(expectedRelevant),'ExpectedPlusCount',numel(expectedPlus), ...
    'ExpectedAxisCount',numel(expectedAxis),'SourceDomainPath',char(domainPath), ...
    'SourceDomainBytes',domainInfo.bytes,'SourceDomainSHA256',hashLocal(domainPath), ...
    'SourceDomainSchemaVersion','G4_GCPC_SOURCE_DOMAIN_TSV_v2_2', ...
    'SourceEventFactsSHA256',char(SourceEventFactsSHA256),'TupleVersion','G4_COMMON_EVENT_TUPLE_v1');
sourceManifestPath=RunPath+".source-chunk-manifest.json";writeJsonLocal(sourceManifestPath,sourceManifest);
sourceManifestSHA=hashLocal(sourceManifestPath);runInfo=dir(RunPath);
runManifest=struct('ManifestVersion','G4_GCPC_SORTED_RUN_MANIFEST_v2_2', ...
    'RunPath',char(RunPath),'RunBytes',runInfo.bytes,'RunSHA256',hashLocal(RunPath), ...
    'SourceChunkIds',double(ChunkId),'SourceChunkManifestPath',char(sourceManifestPath), ...
    'SourceChunkManifestSHA256',sourceManifestSHA,'RecordCount',lineCount, ...
    'ExpectedRecordCount',numel(expectedRelevant),'ActualRecordCount',numel(actualPlus)+numel(actualAxis), ...
    'RecordSchemaVersion','G4_GCPC_EXACT_TSV_HEX_v2_2', ...
    'CanonicalTupleVersion','G4_COMMON_EVENT_TUPLE_v1', ...
    'ActualMapAuthorityVersion',char(string(ActualMap.MapAuthorityVersion)), ...
    'Sorted',true,'HashUsedAsSoleEqualityAuthority',false);
runManifestPath=RunPath+".run-manifest.json";writeJsonLocal(runManifestPath,runManifest);
Envelope=struct('EnvelopeVersion','G4_GCPC_RUN_MANIFEST_ENVELOPE_v2_2', ...
    'ChunkId',double(ChunkId),'ChunkStartIndex',double(SourceIndices(1)), ...
    'ChunkEndIndex',double(SourceIndices(end)),'ChunkSourceEventCount',numel(SourceIndices), ...
    'RunManifestPath',char(runManifestPath),'RunManifestSHA256',hashLocal(runManifestPath), ...
    'ManifestPath',char(runManifestPath),'ManifestSHA256',hashLocal(runManifestPath), ...
    'RunPath',char(RunPath),'RunSHA256',runManifest.RunSHA256,'RecordCount',lineCount, ...
    'SourceChunkManifestPath',char(sourceManifestPath),'SourceChunkManifestSHA256',sourceManifestSHA);
end

function [lines,record]=appendActualLocal(lines,record,indices,population,sourceIndices,tuples,chunkId,tab)
for k=1:numel(indices)
    local=find(sourceIndices==indices(k),1);
    assert(~isempty(local),'G4GCPCv22:ActualIndexOutsideChunk', ...
        'ActualMap SourceIndex %s is not in this chunk.',string(indices(k)));
    record=record+1;lines(record)=utf8HexLocal(tuples(local))+tab+population+tab+string(indices(k))+tab+string(chunkId);
end
end
function text=utf8HexLocal(tuple)
bytes=unicode2native(char(tuple),'UTF-8');text=string(lower(reshape(dec2hex(bytes,2).',1,[])));
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
