function Verdict=VerifyGlobalCompactM0CPairing_v2_2(ChunkRunEnvelopes,LineageManifestPath,LineageManifestSHA256,TotalSourceEventCount,FailClosed)
%VerifyGlobalCompactM0CPairing_v2_2 Fail-closed record/manifest/source closure.
arguments
    ChunkRunEnvelopes (:,1) struct
    LineageManifestPath (1,1) string
    LineageManifestSHA256 (1,1) string
    TotalSourceEventCount (1,1) uint64
    FailClosed (1,1) logical = true
end
timer=tic;process=System.Diagnostics.Process.GetCurrentProcess();process.Refresh();private0=double(process.PrivateMemorySize64);
V=initialVerdictLocal(double(TotalSourceEventCount));n=numel(ChunkRunEnvelopes);
sourceManifests=cell(n,1);runManifests=cell(n,1);manifestSHA=strings(n,1);runSHA=strings(n,1);
for k=1:n
    e=ChunkRunEnvelopes(k);manifestSHA(k)=string(e.ManifestSHA256);
    if ~isfile(e.ManifestPath),V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;continue,end
    if ~strcmp(hashLocal(e.ManifestPath),char(string(e.ManifestSHA256))),V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;end
    try,rm=jsondecode(fileread(e.ManifestPath));runManifests{k}=rm;catch,V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;continue,end
    if ~all(isfield(rm,{'RunPath','RunBytes','RunSHA256','RecordCount','RecordSchemaVersion','CanonicalTupleVersion','SourceChunkManifestPath','SourceChunkManifestSHA256'}))
        V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;continue
    end
    runSHA(k)=string(rm.RunSHA256);
    if ~isfile(rm.RunPath),V.RunSHAMismatchCount=V.RunSHAMismatchCount+1;
    else
        info=dir(rm.RunPath);if info.bytes~=double(rm.RunBytes)||~strcmp(hashLocal(rm.RunPath),rm.RunSHA256),V.RunSHAMismatchCount=V.RunSHAMismatchCount+1;end
    end
    if ~strcmp(rm.RecordSchemaVersion,'G4_GCPC_EXACT_TSV_HEX_v2_2')||~strcmp(rm.CanonicalTupleVersion,'G4_COMMON_EVENT_TUPLE_v1'),V.MergeLineageMismatchCount=V.MergeLineageMismatchCount+1;end
    if ~isfile(rm.SourceChunkManifestPath),V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;continue,end
    if ~strcmp(hashLocal(rm.SourceChunkManifestPath),rm.SourceChunkManifestSHA256),V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;end
    try,sm=jsondecode(fileread(rm.SourceChunkManifestPath));sourceManifests{k}=sm;catch,V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;end
end

validSource=~cellfun(@isempty,sourceManifests);sms=[sourceManifests{validSource}];
if isempty(sms),V.ManifestRangesCoverSourceDomainExactlyOnce=false;ids=[];
else
    ids=[sms.ChunkId];V.DuplicateManifestChunkIdCount=numel(ids)-numel(unique(ids));
    [~,order]=sort([sms.ChunkStartIndex]);sorted=sms(order);cover=sorted(1).ChunkStartIndex==1&&sorted(end).ChunkEndIndex==double(TotalSourceEventCount);
    for k=2:numel(sorted),cover=cover&&sorted(k).ChunkStartIndex==sorted(k-1).ChunkEndIndex+1;end
    cover=cover&&sum([sorted.ChunkSourceEventCount])==double(TotalSourceEventCount)&&V.DuplicateManifestChunkIdCount==0;
    V.ManifestRangesCoverSourceDomainExactlyOnce=cover;
end

expectedSide=zeros(double(TotalSourceEventCount),1,'uint8');
for k=1:numel(sms)
    sm=sms(k);
    if ~all(isfield(sm,{'SourceDomainPath','SourceDomainBytes','SourceDomainSHA256','ChunkStartIndex','ChunkEndIndex','RelevantSourceEventCount'})),V.SourceDomainSHAMismatchCount=V.SourceDomainSHAMismatchCount+1;continue,end
    if ~isfile(sm.SourceDomainPath),V.SourceDomainSHAMismatchCount=V.SourceDomainSHAMismatchCount+1;continue,end
    di=dir(sm.SourceDomainPath);if di.bytes~=double(sm.SourceDomainBytes)||~strcmp(hashLocal(sm.SourceDomainPath),sm.SourceDomainSHA256),V.SourceDomainSHAMismatchCount=V.SourceDomainSHAMismatchCount+1;continue,end
    fid=fopen(sm.SourceDomainPath,'r','n','UTF-8');c=onCleanup(@()fclose(fid));rows=0;
    while true
        line=fgetl(fid);if ~ischar(line),break,end;parts=split(string(line),sprintf('\t'));rows=rows+1;
        if numel(parts)~=2, V.SourceDomainInvalidRecordCount=V.SourceDomainInvalidRecordCount+1;continue,end
        idx=parseIntegerLocal(parts(1));side=parts(2);
        if isnan(idx)||idx<sm.ChunkStartIndex||idx>sm.ChunkEndIndex||idx<1||idx>double(TotalSourceEventCount)||~any(side==["PLUS","AXIS"])
            V.SourceDomainInvalidRecordCount=V.SourceDomainInvalidRecordCount+1;continue
        end
        if expectedSide(idx)~=0,V.SourceDomainDuplicateIndexCount=V.SourceDomainDuplicateIndexCount+1;end
        expectedSide(idx)=uint8(1+(side=="AXIS"));
    end
    clear c
    if rows~=double(sm.RelevantSourceEventCount),V.SourceDomainInvalidRecordCount=V.SourceDomainInvalidRecordCount+1;end
end
V.ExpectedRelevantSourceEventCount=nnz(expectedSide);

lineage=[];
if ~isfile(LineageManifestPath)||~strcmp(hashLocal(LineageManifestPath),char(LineageManifestSHA256)),V.MergeLineageMismatchCount=V.MergeLineageMismatchCount+1;
else
    try,lineage=jsondecode(fileread(LineageManifestPath));catch,V.MergeLineageMismatchCount=V.MergeLineageMismatchCount+1;end
end
finalRunPath="";finalManifest=[];
if ~isempty(lineage)
    required={'OrderedBaseRunSHA256','OrderedBaseRunManifestSHA256','FinalRunPath','FinalRunBytes','FinalRunSHA256','FinalRunRecordCount','FinalRunManifestPath','FinalRunManifestSHA256'};
    if ~all(isfield(lineage,required)),V.MergeLineageMismatchCount=V.MergeLineageMismatchCount+1;
    else
        if ~isequal(string(lineage.OrderedBaseRunManifestSHA256(:)),manifestSHA)||~isequal(string(lineage.OrderedBaseRunSHA256(:)),runSHA),V.MergeLineageMismatchCount=V.MergeLineageMismatchCount+1;end
        if ~isfile(lineage.FinalRunManifestPath)||~strcmp(hashLocal(lineage.FinalRunManifestPath),lineage.FinalRunManifestSHA256),V.RunManifestSHAMismatchCount=V.RunManifestSHAMismatchCount+1;
        else
            finalManifest=jsondecode(fileread(lineage.FinalRunManifestPath));
            if ~strcmp(lineage.FinalRunManifestSHA256,hashLocal(lineage.FinalRunManifestPath)),V.MergeLineageMismatchCount=V.MergeLineageMismatchCount+1;end
        end
        finalRunPath=string(lineage.FinalRunPath);
        if ~isfile(finalRunPath),V.RunSHAMismatchCount=V.RunSHAMismatchCount+1;
        else
            fi=dir(finalRunPath);actualSHA=hashLocal(finalRunPath);
            if fi.bytes~=double(lineage.FinalRunBytes)||~strcmp(actualSHA,lineage.FinalRunSHA256),V.RunSHAMismatchCount=V.RunSHAMismatchCount+1;end
            if ~isempty(finalManifest)&&(~strcmp(finalManifest.RunSHA256,lineage.FinalRunSHA256)||double(finalManifest.RunBytes)~=double(lineage.FinalRunBytes)||double(finalManifest.RecordCount)~=double(lineage.FinalRunRecordCount)),V.MergeLineageMismatchCount=V.MergeLineageMismatchCount+1;end
        end
    end
end

expectedCount=zeros(double(TotalSourceEventCount),1,'uint16');actualCount=zeros(double(TotalSourceEventCount),1,'uint16');
recordTimer=tic;previousLine='';currentTuple='';groupPops=strings(0,1);groupIndices=zeros(0,1,'uint64');groupSides=strings(0,1);groupInvalid=false;
if isfile(finalRunPath)
    fid=fopen(finalRunPath,'r','n','UTF-8');cleanup=onCleanup(@()fclose(fid));
    while true
        line=fgetl(fid);if ~ischar(line),break,end;V.MergedRecordCount=V.MergedRecordCount+1;
        if ~isempty(previousLine)&&lexCompareLocal(previousLine,line)>0,V.SortedRunExact=false;end;previousLine=line;
        parts=split(string(line),sprintf('\t'));
        if numel(parts)~=4||mod(strlength(parts(1)),2)~=0||isempty(regexp(char(parts(1)),'^[0-9a-f]+$','once')) %#ok<RGXP1>
            V.InvalidRecordFormatCount=V.InvalidRecordFormatCount+1;V.InvalidGroups=V.InvalidGroups+1;continue
        end
        tupleHex=char(parts(1));population=parts(2);idx=parseIntegerLocal(parts(3));chunk=parseIntegerLocal(parts(4));
        if isempty(currentTuple),currentTuple=tupleHex;end
        if ~strcmp(tupleHex,currentTuple)
            V=closeGroupLocal(V,groupPops,groupIndices,groupSides,groupInvalid);currentTuple=tupleHex;groupPops=strings(0,1);groupIndices=zeros(0,1,'uint64');groupSides=strings(0,1);groupInvalid=false;
        end
        allowed=["PLUS_EXPECTED","PLUS_ACTUAL","AXIS_EXPECTED","AXIS_ACTUAL"];
        populationValid=any(population==allowed);if ~populationValid,V.InvalidPopulationCount=V.InvalidPopulationCount+1;groupInvalid=true;end
        tupleSide=tupleSideLocal(tupleHex);if tupleSide=="INVALID",V.InvalidTupleSideCount=V.InvalidTupleSideCount+1;groupInvalid=true;end
        expectedPopulationSide="INVALID";if startsWith(population,"PLUS_"),expectedPopulationSide="PLUS";elseif startsWith(population,"AXIS_"),expectedPopulationSide="AXIS";end
        if populationValid&&tupleSide~=expectedPopulationSide,V.PopulationTupleSideMismatchCount=V.PopulationTupleSideMismatchCount+1;groupInvalid=true;end
        idxValid=~isnan(idx)&&idx>=1&&idx<=double(TotalSourceEventCount);
        chunkMatch=find(ids==chunk);
        if isnan(chunk)||isempty(chunkMatch),V.UnknownChunkIdCount=V.UnknownChunkIdCount+1;groupInvalid=true;
        elseif idxValid
            sm=sms(chunkMatch(1));if idx<sm.ChunkStartIndex||idx>sm.ChunkEndIndex,V.SourceIndexOutsideDeclaredChunkCount=V.SourceIndexOutsideDeclaredChunkCount+1;groupInvalid=true;end
        end
        if ~idxValid,V.GlobalUnexpectedSourceIndexCount=V.GlobalUnexpectedSourceIndexCount+1;groupInvalid=true;
        elseif expectedSide(idx)==0,V.GlobalUnexpectedSourceIndexCount=V.GlobalUnexpectedSourceIndexCount+1;groupInvalid=true;
        elseif populationValid
            expectedTruthSide="PLUS";if expectedSide(idx)==2,expectedTruthSide="AXIS";end
            if expectedPopulationSide~=expectedTruthSide,V.SourceIndexPopulationSideMismatchCount=V.SourceIndexPopulationSideMismatchCount+1;groupInvalid=true;end
            if endsWith(population,"_EXPECTED"),expectedCount(idx)=expectedCount(idx)+1;else,actualCount(idx)=actualCount(idx)+1;end
        end
        groupPops(end+1,1)=population;groupIndices(end+1,1)=uint64(max(idx,0));groupSides(end+1,1)=tupleSide;
    end
    if ~isempty(currentTuple),V=closeGroupLocal(V,groupPops,groupIndices,groupSides,groupInvalid);end
    clear cleanup
end
V.RecordValidationSeconds=toc(recordTimer);mask=expectedSide>0;
V.GlobalMissingExpectedSourceIndexCount=nnz(mask&expectedCount==0);V.GlobalMissingActualSourceIndexCount=nnz(mask&actualCount==0);
V.GlobalDuplicateExpectedSourceIndexCount=nnz(mask&expectedCount>1);V.GlobalDuplicateActualSourceIndexCount=nnz(mask&actualCount>1);
V.GlobalExpectedActualSourceIndexMismatchCount=V.GroupExpectedActualSourceIndexMismatchCount+nnz(mask&expectedCount~=actualCount);
if sum(expectedCount)==sum(actualCount)&&sum(expectedCount)==nnz(mask)&&(V.GlobalMissingExpectedSourceIndexCount+V.GlobalMissingActualSourceIndexCount+V.GlobalDuplicateExpectedSourceIndexCount+V.GlobalDuplicateActualSourceIndexCount)>0
    V.EqualCountSubstitutionDetectedCount=V.GlobalMissingExpectedSourceIndexCount+V.GlobalMissingActualSourceIndexCount+V.GlobalDuplicateExpectedSourceIndexCount+V.GlobalDuplicateActualSourceIndexCount;
else,V.EqualCountSubstitutionDetectedCount=V.GroupEqualCountSubstitutionCount;end
V.RecordSourceIndicesCoverExpectedDomainExactlyOnce=V.GlobalMissingExpectedSourceIndexCount==0&&V.GlobalMissingActualSourceIndexCount==0&&V.GlobalDuplicateExpectedSourceIndexCount==0&&V.GlobalDuplicateActualSourceIndexCount==0&&V.GlobalUnexpectedSourceIndexCount==0;
V.AllSourceIndicesCoveredExactlyOnce=V.ManifestRangesCoverSourceDomainExactlyOnce&&V.RecordSourceIndicesCoverExpectedDomainExactlyOnce;
V.ExpectedRecordCount=2*nnz(mask);V.FinalMergedRunSHA256=char(string(getFieldLocal(lineage,'FinalRunSHA256','')));V.FinalMergedRunManifestSHA256=char(string(getFieldLocal(lineage,'FinalRunManifestSHA256','')));
V.PASS=V.AllSourceIndicesCoveredExactlyOnce&&V.SortedRunExact&&V.MergedRecordCount==V.ExpectedRecordCount&& ...
    V.InvalidRecordFormatCount==0&&V.InvalidPopulationCount==0&&V.InvalidTupleSideCount==0&& ...
    V.PopulationTupleSideMismatchCount==0&&V.UnknownChunkIdCount==0&&V.DuplicateManifestChunkIdCount==0&& ...
    V.SourceIndexOutsideDeclaredChunkCount==0&&V.SourceIndexPopulationSideMismatchCount==0&& ...
    V.GlobalExpectedActualSourceIndexMismatchCount==0&&V.EqualCountSubstitutionDetectedCount==0&&V.InvalidGroups==0&& ...
    V.RunSHAMismatchCount==0&&V.RunManifestSHAMismatchCount==0&&V.MergeLineageMismatchCount==0&& ...
    V.SourceDomainSHAMismatchCount==0&&V.SourceDomainInvalidRecordCount==0&&V.SourceDomainDuplicateIndexCount==0;
V.TotalVerificationSeconds=toc(timer);process.Refresh();V.PrivateBytesBefore=private0;V.PrivateBytesAfter=double(process.PrivateMemorySize64);V.PeakWorkingSetBytes=double(process.PeakWorkingSet64);V.WorkingSetBytes=double(process.WorkingSet64);
if FailClosed,assert(V.PASS,'G4GCPCv22:FailClosedVerdict','GCPC v2.2 fail-closed record-content verdict failed.');end
Verdict=V;
end

function V=closeGroupLocal(V,pops,indices,sides,invalid)
if isempty(pops),return,end
legal=ismember(pops,["PLUS_EXPECTED","PLUS_ACTUAL","AXIS_EXPECTED","AXIS_ACTUAL"]);
if invalid||~all(legal)||numel(unique(sides(sides~="INVALID")))~=1,V.InvalidGroups=V.InvalidGroups+1;end
e=sort(indices(endsWith(pops,"_EXPECTED")&legal));a=sort(indices(endsWith(pops,"_ACTUAL")&legal));
if ~isequal(e,a),V.GroupExpectedActualSourceIndexMismatchCount=V.GroupExpectedActualSourceIndexMismatchCount+multisetDistanceLocal(e,a);if numel(e)==numel(a),V.GroupEqualCountSubstitutionCount=V.GroupEqualCountSubstitutionCount+1;end,end
end
function d=multisetDistanceLocal(a,b)
i=1;j=1;d=0;while i<=numel(a)||j<=numel(b),if i>numel(a),d=d+numel(b)-j+1;break;elseif j>numel(b),d=d+numel(a)-i+1;break;elseif a(i)==b(j),i=i+1;j=j+1;elseif a(i)<b(j),d=d+1;i=i+1;else,d=d+1;j=j+1;end,end
end
function side=tupleSideLocal(hex)
side="INVALID";try,text=native2unicode(uint8(sscanf(hex,'%2x').'),'UTF-8');token=regexp(text,'^side=(PLUS|AXIS)\|','tokens','once');if ~isempty(token),side=string(token{1});end,catch,end
end
function value=parseIntegerLocal(text)
value=str2double(text);if ~isfinite(value)||value<0||value~=fix(value),value=NaN;end
end
function value=getFieldLocal(s,name,default),if isstruct(s)&&isfield(s,name),value=s.(name);else,value=default;end,end
function cmp=lexCompareLocal(a,b)
aa=unicode2native(a,'UTF-8');bb=unicode2native(b,'UTF-8');n=min(numel(aa),numel(bb));q=find(aa(1:n)~=bb(1:n),1);if isempty(q),cmp=sign(numel(aa)-numel(bb));else,cmp=sign(double(aa(q))-double(bb(q)));end
end
function sha=hashLocal(path)
md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'r');assert(fid>=0,'G4GCPCv22:HashOpen','Cannot hash %s.',path);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true,d=fread(fid,1024*1024,'*uint8');if isempty(d),break;end;md.update(typecast(d,'int8'));end;sha=char(lower(reshape(dec2hex(mod(double(md.digest()),256),2).',1,[])));
end
function V=initialVerdictLocal(total)
V=struct('VerdictVersion','G4_GCPC_FAIL_CLOSED_RECORD_CONTENT_v2_2','TupleVersion','G4_COMMON_EVENT_TUPLE_v1', ...
    'TotalSourceEventCount',total,'ManifestRangesCoverSourceDomainExactlyOnce',false,'RecordSourceIndicesCoverExpectedDomainExactlyOnce',false,'AllSourceIndicesCoveredExactlyOnce',false, ...
    'ExpectedRelevantSourceEventCount',0,'ExpectedRecordCount',0,'MergedRecordCount',0,'SortedRunExact',true, ...
    'InvalidRecordFormatCount',0,'InvalidPopulationCount',0,'InvalidTupleSideCount',0,'PopulationTupleSideMismatchCount',0, ...
    'UnknownChunkIdCount',0,'DuplicateManifestChunkIdCount',0,'SourceIndexOutsideDeclaredChunkCount',0,'SourceIndexPopulationSideMismatchCount',0, ...
    'GlobalMissingExpectedSourceIndexCount',0,'GlobalMissingActualSourceIndexCount',0,'GlobalDuplicateExpectedSourceIndexCount',0,'GlobalDuplicateActualSourceIndexCount',0, ...
    'GlobalExpectedActualSourceIndexMismatchCount',0,'GlobalUnexpectedSourceIndexCount',0,'EqualCountSubstitutionDetectedCount',0, ...
    'GroupExpectedActualSourceIndexMismatchCount',0,'GroupEqualCountSubstitutionCount',0,'InvalidGroups',0, ...
    'RunSHAMismatchCount',0,'RunManifestSHAMismatchCount',0,'MergeLineageMismatchCount',0, ...
    'SourceDomainSHAMismatchCount',0,'SourceDomainInvalidRecordCount',0,'SourceDomainDuplicateIndexCount',0, ...
    'FinalMergedRunSHA256','','FinalMergedRunManifestSHA256','','RecordValidationSeconds',NaN,'TotalVerificationSeconds',NaN, ...
    'PrivateBytesBefore',NaN,'PrivateBytesAfter',NaN,'PeakWorkingSetBytes',NaN,'WorkingSetBytes',NaN, ...
    'HashUsedAsSoleEqualityAuthority',false,'ExactTupleComparisonAuthoritative',true,'PASS',false);
end
