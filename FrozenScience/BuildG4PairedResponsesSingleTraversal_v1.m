function Paired = BuildG4PairedResponsesSingleTraversal_v1(InputParams,TempWorkDir,Contract,ManifestStem)
%BuildG4PairedResponsesSingleTraversal_v1 One M2 traversal, explicit M0-C copy.
arguments
    InputParams (1,1) struct
    TempWorkDir (1,1) string
    Contract (1,1) struct
    ManifestStem (1,1) string = ""
end
assert(Contract.G4ScientificExecutionAuthorized, ...
    'G4P0v5:ScientificExecutionLocked','v5 contract forbids scientific execution.');
InputParams.ScatterGrid.RandomModel='event_white_phase';
InputParams.ScatterGrid.RandomModelVersion=Contract.RandomModelVersion;
InputParams.Model.DisableAdditionalRandomPhase=false;
% Exactly one stochastic traversal. Event table and h(t) are co-produced.
[~,hM2,hDir,m2Events,~,directEvents,randomInfo,~,gridAudit]= ...
    ImpulseResponse(InputParams,1,TempWorkDir);
assert(randomInfo.RandomModelVersion==Contract.RandomModelVersion, ...
    'G4P0v5:RandomModelVersionMismatch');
m0cEvents=BuildProductionM0CFromM2Events_v1(m2Events);
manifest=VerifyRuntimeCommonEventPairingGate_v1(randomInfo.RandomSeedUsed, ...
    m0cEvents,m2Events,"G4_COMMON_EVENT_TUPLE_v1",Contract.ActiveSourceSHAs,ManifestStem);
% M0-C h(t) comes from the explicit mirror-copy event table; no rerun.
hM0C=BuildImpulseResponseFromEvents(m0cEvents,InputParams.fs,numel(hM2));
Paired=struct('RandomInfo',randomInfo,'M0CEvents',m0cEvents,'M2Events',m2Events, ...
    'M0ChSca',hM0C,'M2hSca',hM2,'CommonhDir',hDir, ...
    'DirectEvents',directEvents,'GridAudit',gridAudit,'PairingManifest',manifest, ...
    'SameTraversalEventTableAndH',true,'SecondRandomDrawPossible',false, ...
    'SaveEventsRerunProhibited',true);
end
