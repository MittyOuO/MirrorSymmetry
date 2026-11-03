function M0CEvents = BuildProductionM0CFromM2Events_v1(M2Events)
%BuildProductionM0CFromM2Events_v1 Explicit coherent mirror-copy branch.
% Negative-side M0-C complex gain and stochastic phase are assigned from
% the authoritative positive-side event. No negative-side PRF draw occurs.
arguments
    M2Events (:,1) struct
end
required={'Y','ComplexGain','RandomBase','RandomPhase','CellKey', ...
    'PathInstanceKey','PathClass','InterfaceType','EventKey'};
for k=1:numel(required)
    assert(isfield(M2Events,required{k}),'G4P0v5:M0CMissingEventField', ...
        'M2 event table lacks required field %s.',required{k});
end
if isempty(M2Events)
    M0CEvents=M2Events;
    return;
end
M2Events=addMetadataFieldsLocal(M2Events);
axisEvents=M2Events([M2Events.Y]==0);
plusEvents=M2Events([M2Events.Y]>0);
M0CEvents=repmat(M2Events(1),0,1);
for k=1:numel(axisEvents)
    ev=axisEvents(k);
    ev.G4ModelIdentity='M0-C';
    ev.M0CBranchRole='AXIS_COUNTED_ONCE';
    ev.M0CMirrorSourceCellKey=ev.CellKey;
    ev.M0CMirrorSourceEventKey=ev.EventKey;
    M0CEvents(end+1,1)=ev; %#ok<AGROW>
end
for k=1:numel(plusEvents)
    plus=plusEvents(k);
    plus.G4ModelIdentity='M0-C';
    plus.M0CBranchRole='COMMON_PLUS_SOURCE';
    plus.M0CMirrorSourceCellKey=plus.CellKey;
    plus.M0CMirrorSourceEventKey=plus.EventKey;
    M0CEvents(end+1,1)=plus; %#ok<AGROW>

    minus=plus;
    minus.Y=-plus.Y;
    if isfield(minus,'PhiS'), minus.PhiS=-plus.PhiS; end
    if isfield(minus,'PhiR'), minus.PhiR=-plus.PhiR; end
    minus.CellKey=BuildScatterCellKey(char(string(plus.InterfaceType)),plus.X,-plus.Y);
    [~,minus.CellId]=StableKeyHash('cell',minus.CellKey);
    minus.G4ModelIdentity='M0-C';
    minus.M0CBranchRole='EXPLICIT_MIRROR_COPY_NEGATIVE';
    minus.M0CMirrorSourceCellKey=plus.CellKey;
    minus.M0CMirrorSourceEventKey=plus.EventKey;
    % Frozen M0-C identity: explicit copy, not negative-key PRF reuse.
    minus.ComplexGain=plus.ComplexGain;
    if isfield(minus,'PowerGain'), minus.PowerGain=abs(plus.ComplexGain)^2; end
    minus.RandomBase=plus.RandomBase;
    minus.RandomPhase=plus.RandomPhase;
    if isfield(minus,'UsesRandomPhase'), minus.UsesRandomPhase=plus.UsesRandomPhase; end
    minus.EventKey=plus.EventKey;
    if isfield(minus,'EventKeyId'), minus.EventKeyId=plus.EventKeyId; end
    M0CEvents(end+1,1)=minus; %#ok<AGROW>
end
assert(sum([M0CEvents.Y]==0)==numel(axisEvents),'G4P0v5:M0CAxisDuplication', ...
    'M0-C axis must be counted exactly once.');
end

function events=addMetadataFieldsLocal(events)
if ~isfield(events,'G4ModelIdentity'),[events.G4ModelIdentity]=deal('');end
if ~isfield(events,'M0CBranchRole'),[events.M0CBranchRole]=deal('');end
if ~isfield(events,'M0CMirrorSourceCellKey'),[events.M0CMirrorSourceCellKey]=deal('');end
if ~isfield(events,'M0CMirrorSourceEventKey'),[events.M0CMirrorSourceEventKey]=deal('');end
end
