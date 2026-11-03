function Manifest = VerifyRuntimeCommonEventPairingGate_v1(Seed,M0CEvents,M2Events,IdentityTupleVersion,SourceSHAs,OutputStem)
%VerifyRuntimeCommonEventPairingGate_v1 Mandatory pre-QoI pairing gate.
arguments
    Seed (1,1) double {mustBeFinite,mustBeNonnegative}
    M0CEvents (:,1) struct
    M2Events (:,1) struct
    IdentityTupleVersion (1,1) string = "G4_COMMON_EVENT_TUPLE_v1"
    SourceSHAs = struct()
    OutputStem (1,1) string = ""
end
plus0=M0CEvents([M0CEvents.Y]>0); plus2=M2Events([M2Events.Y]>0);
axis0=M0CEvents([M0CEvents.Y]==0); axis2=M2Events([M2Events.Y]==0);
keysPlus0=sort(identityKeysLocal(plus0));
keysPlus2=sort(identityKeysLocal(plus2));
keysAxis0=sort(identityKeysLocal(axis0));
keysAxis2=sort(identityKeysLocal(axis2));
plusMatched=multisetMatchedCountLocal(keysPlus0,keysPlus2);
axisMatched=multisetMatchedCountLocal(keysAxis0,keysAxis2);
axisUnique0=numel(unique(keysAxis0))==numel(keysAxis0);
axisUnique2=numel(unique(keysAxis2))==numel(keysAxis2);
plusExact=isequal(keysPlus0,keysPlus2);
axisExact=isequal(keysAxis0,keysAxis2) && axisUnique0 && axisUnique2;
mismatch=(numel(keysPlus0)-plusMatched)+(numel(keysPlus2)-plusMatched)+ ...
    (numel(keysAxis0)-axisMatched)+(numel(keysAxis2)-axisMatched);
if ~axisUnique0 || ~axisUnique2, mismatch=mismatch+1; end
status='PASS';
if ~plusExact, status='HARD_FAIL_COMMON_PLUS_IDENTITY_MISMATCH'; end
if ~axisExact, status='HARD_FAIL_AXIS_IDENTITY_MISMATCH_OR_DUPLICATION'; end
Manifest=struct('Seed',Seed,'CommonPlusCountM0C',numel(keysPlus0), ...
    'CommonPlusCountM2',numel(keysPlus2),'CommonPlusExactMatchedCount',plusMatched, ...
    'AxisCountM0C',numel(keysAxis0),'AxisCountM2',numel(keysAxis2), ...
    'AxisExactMatchedCount',axisMatched,'MismatchCount',mismatch, ...
    'PairingGateStatus',status,'IdentityTupleVersion',char(IdentityTupleVersion), ...
    'SourceSHAs',SourceSHAs);
if strlength(OutputStem)>0, persistManifestLocal(Manifest,OutputStem); end
assert(plusExact,'G4P0v5:CommonPlusPairingGateFailed', ...
    'Common +y event identity mismatch; seed is invalid and must not be replaced.');
assert(axisExact,'G4P0v5:AxisPairingGateFailed', ...
    'Axis identity mismatch/duplication; seed is invalid and must not be replaced.');
end

function keys=identityKeysLocal(events)
required={'Y','CellKey','PathInstanceKey','PathClass','InterfaceType', ...
    'DelayIn','DelayOut','NumBotIn','NumTopIn','NumBotOut','NumTopOut'};
for k=1:numel(required)
    assert(isfield(events,required{k}),'G4P0v5:PairingFieldMissing', ...
        'Pairing identity field missing: %s.',required{k});
end
keys=strings(numel(events),1);
for k=1:numel(events)
    e=events(k);
    side='AXIS'; if e.Y>0,side='PLUS';elseif e.Y<0,side='MINUS';end
    keys(k)=string(sprintf(['side=%s|cell=%s|path=%s|class=%s|interface=%s|', ...
        'delayIn=%.17g|delayOut=%.17g|Bi=%.17g|Ti=%.17g|Bo=%.17g|To=%.17g'], ...
        side,char(string(e.CellKey)),char(string(e.PathInstanceKey)), ...
        char(string(e.PathClass)),char(string(e.InterfaceType)),double(e.DelayIn), ...
        double(e.DelayOut),double(e.NumBotIn),double(e.NumTopIn), ...
        double(e.NumBotOut),double(e.NumTopOut)));
end
end

function n=multisetMatchedCountLocal(a,b)
[ua,~,~]=unique(a); [ub,~,~]=unique(b); allKeys=union(ua,ub); n=0;
for k=1:numel(allKeys)
    n=n+min(sum(a==allKeys(k)),sum(b==allKeys(k)));
end
end

function persistManifestLocal(manifest,stem)
stem=char(stem); folder=fileparts(stem); if ~isempty(folder)&&exist(folder,'dir')~=7,mkdir(folder);end
writetable(struct2table(rmfield(manifest,'SourceSHAs')), [stem,'.csv']);
fid=fopen([stem,'.json'],'w'); assert(fid>=0,'G4P0v5:ManifestWriteFailed');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(manifest,'PrettyPrint',true));
end
