function [Compact,MirrorCache] = BuildCompactM0CAuthorityFromM2Facts_v1(M2Events,SourceIndices,MirrorCache,SourceEventFactsSHA)
%BuildCompactM0CAuthorityFromM2Facts_v1 Bounded-chunk M0-C mirror authority.
% No complete mirror-minus event struct array is created. Unchanged fields
% remain exact references to immutable M2 source indices. Mirror CellKey and
% CellId are calculated once per unique positive-side source cell.
arguments
    M2Events (:,1) struct
    SourceIndices (:,1) uint64 = uint64.empty(0,1)
    MirrorCache (1,1) struct = struct()
    SourceEventFactsSHA (1,1) string = ""
end
required={'Y','X','ComplexGain','RandomBase','RandomPhase','CellKey', ...
    'PathInstanceKey','PathClass','InterfaceType','EventKey','Delay', ...
    'DelayIn','DelayOut','NumBotIn','NumTopIn','NumBotOut','NumTopOut'};
for k=1:numel(required)
    assert(isfield(M2Events,required{k}),'G4CR:CompactMissingEventField', ...
        'M2 event chunk lacks required field %s.',required{k});
end
if isempty(SourceIndices)
    SourceIndices=uint64((1:numel(M2Events)).');
end
assert(numel(SourceIndices)==numel(M2Events) && numel(unique(SourceIndices))==numel(SourceIndices), ...
    'G4CR:SourceIndexIdentity','Source indices must be unique and one-to-one with the chunk.');
if isempty(fieldnames(MirrorCache)), MirrorCache=emptyCacheLocal(); end
validateCacheLocal(MirrorCache);

y=reshape(double([M2Events.Y]),[],1);
assert(all(isfinite(y)),'G4CR:NonfiniteGeometry','Event Y must be finite.');
plusLocal=find(y>0);
axisLocal=find(y==0);
plus=M2Events(plusLocal);

sourceKeys=reshape(string({plus.CellKey}),[],1);
if isempty(sourceKeys)
    uniqueKeys=strings(0,1); firstLocal=zeros(0,1); within=zeros(0,1);
else
    [uniqueKeys,firstLocal,within]=unique(sourceKeys,'sorted');
end
mapForUnique=zeros(numel(uniqueKeys),1,'uint32');
for u=1:numel(uniqueKeys)
    members=find(within==u);
    first=plus(members(1));
    x=double(first.X); sourceY=double(first.Y); interface=string(first.InterfaceType);
    assert(isfinite(x)&&isfinite(sourceY)&&sourceY>0,'G4CR:InvalidPlusGeometry', ...
        'Positive-side source cell geometry is invalid.');
    for q=2:numel(members)
        e=plus(members(q));
        assert(double(e.X)==x && double(e.Y)==sourceY && string(e.InterfaceType)==interface, ...
            'G4CR:SourceCellGeometryConflict','One CellKey maps to inconsistent source geometry.');
    end
    existing=find(MirrorCache.SourceCellKey==uniqueKeys(u),1);
    mirrorY=-sourceY;
    mirrorKey=string(BuildScatterCellKey(char(interface),x,mirrorY));
    [~,mirrorId]=StableKeyHash('cell',mirrorKey);
    if isempty(existing)
        MirrorCache.SourceCellKey(end+1,1)=uniqueKeys(u);
        MirrorCache.InterfaceType(end+1,1)=interface;
        MirrorCache.X(end+1,1)=x;
        MirrorCache.SourceY(end+1,1)=sourceY;
        MirrorCache.MirrorY(end+1,1)=mirrorY;
        MirrorCache.MirrorCellKey(end+1,1)=mirrorKey;
        MirrorCache.MirrorCellId(end+1,1)=mirrorId;
        existing=numel(MirrorCache.SourceCellKey);
    else
        assert(MirrorCache.InterfaceType(existing)==interface && ...
            MirrorCache.X(existing)==x && MirrorCache.SourceY(existing)==sourceY && ...
            MirrorCache.MirrorY(existing)==mirrorY && ...
            MirrorCache.MirrorCellKey(existing)==mirrorKey && ...
            MirrorCache.MirrorCellId(existing)==mirrorId, ...
            'G4CR:MirrorCacheConflict','Existing mirror-cell cache entry is not exact.');
    end
    mapForUnique(u)=uint32(existing);
end

eventMap=zeros(numel(plusLocal),1,'uint32');
if ~isempty(within), eventMap=mapForUnique(within); end
mirrorPhiS=[]; mirrorPhiR=[];
if isfield(M2Events,'PhiS'), mirrorPhiS=-reshape(double([plus.PhiS]),[],1); end
if isfield(M2Events,'PhiR'), mirrorPhiR=-reshape(double([plus.PhiR]),[],1); end

Compact=struct();
Compact.AuthorityVersion='G4_COMPACT_M0C_AUTHORITY_v1';
Compact.Representation='BOUNDED_CHUNK_SOURCE_REFERENCE_PLUS_UNIQUE_MIRROR_CELL_CACHE';
Compact.SourceEventFactsSHA256=char(SourceEventFactsSHA);
Compact.TupleVersion='G4_COMMON_EVENT_TUPLE_v1';
Compact.SourceIndices=SourceIndices;
Compact.AxisSourceIndices=SourceIndices(axisLocal);
Compact.PlusSourceIndices=SourceIndices(plusLocal);
Compact.AxisLocalIndices=uint32(axisLocal);
Compact.PlusLocalIndices=uint32(plusLocal);
Compact.M0CBranchRole=struct('Axis','AXIS_COUNTED_ONCE', ...
    'Plus','COMMON_PLUS_SOURCE','Mirror','EXPLICIT_MIRROR_COPY_NEGATIVE');
Compact.MirrorCellMapIndex=eventMap;
Compact.UniqueMirrorCellMap=MirrorCache;
Compact.MirrorY=-y(plusLocal);
Compact.MirrorPhiS=mirrorPhiS;
Compact.MirrorPhiR=mirrorPhiR;
Compact.SourceIdentityTuple=struct('Representation','EXACT_SOURCE_INDEX_REFERENCE', ...
    'TupleVersion','G4_COMMON_EVENT_TUPLE_v1','Indices',[Compact.AxisSourceIndices;Compact.PlusSourceIndices]);
Compact.MirrorIdentityTuple=struct('Representation','EXACT_TRANSFORM_REFERENCE', ...
    'TupleVersion','G4_M0C_MIRROR_TRANSFORM_v1','PlusSourceIndices',Compact.PlusSourceIndices, ...
    'MirrorCellMapIndex',eventMap);
Compact.CopyRules=struct('Delay','COPY_SOURCE','ComplexGain','COPY_SOURCE', ...
    'RandomBase','COPY_SOURCE','RandomPhase','COPY_SOURCE','EventKey','COPY_SOURCE', ...
    'PathInstanceKey','COPY_SOURCE','PathClass','COPY_SOURCE','InterfaceType','COPY_SOURCE');
Compact.TransformRules=struct('Y','NEGATE_SOURCE','PhiS','NEGATE_IF_PRESENT', ...
    'PhiR','NEGATE_IF_PRESENT','CellKey','BUILD_SCATTER_CELL_KEY_FROM_INTERFACE_X_NEGATIVE_Y', ...
    'CellId','STABLE_KEY_HASH_CELL_OF_MIRROR_CELL_KEY');
Compact.Counts=struct('InputEvents',numel(M2Events),'AxisEvents',numel(axisLocal), ...
    'PlusEvents',numel(plusLocal),'IgnoredM2MinusEvents',sum(y<0), ...
    'UniquePlusCellsInChunk',numel(uniqueKeys),'MirrorCacheEntries',numel(MirrorCache.SourceCellKey), ...
    'HashCallsThisChunk',sum(firstLocal>0));
Compact.FullM0CEventsMaterializationRequired=false;
Compact.FullM0CEventsCriticalPath=false;
Compact.FullM0CEventsRetentionRole='OPTIONAL_DERIVED_CACHE';
end

function cache=emptyCacheLocal()
cache=struct('SourceCellKey',strings(0,1),'InterfaceType',strings(0,1), ...
    'X',zeros(0,1),'SourceY',zeros(0,1),'MirrorY',zeros(0,1), ...
    'MirrorCellKey',strings(0,1),'MirrorCellId',zeros(0,1));
end

function validateCacheLocal(cache)
required={'SourceCellKey','InterfaceType','X','SourceY','MirrorY','MirrorCellKey','MirrorCellId'};
for k=1:numel(required),assert(isfield(cache,required{k}),'G4CR:MirrorCacheSchema','Missing cache field %s.',required{k});end
n=numel(cache.SourceCellKey);
for k=2:numel(required),assert(numel(cache.(required{k}))==n,'G4CR:MirrorCacheSchema','Mirror cache columns differ in length.');end
assert(numel(unique(cache.SourceCellKey))==n,'G4CR:MirrorCacheDuplicate','Mirror cache source keys must be unique.');
end
