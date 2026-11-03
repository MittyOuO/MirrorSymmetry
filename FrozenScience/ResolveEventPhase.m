function Phase = ResolveEventPhase(RandomInfo,interfaceType,cellKey,pathInstanceKey,disableAdditionalRandomPhase)
%ResolveEventPhase Select deterministic M1 or frozen M2 event phase.

[randomBase,eventKey,eventKeyId]=ScatterEventRandomUnit( ...
    RandomInfo.RandomSeedUsed,interfaceType,cellKey,pathInstanceKey, ...
    RandomInfo.RandomModelVersion);
disableAdditionalRandomPhase=logical(disableAdditionalRandomPhase);
if disableAdditionalRandomPhase
    randomPhase=0; multiplier=complex(1); uses=false;
else
    randomPhase=2*pi*randomBase; multiplier=exp(1i*randomPhase); uses=true;
end
Phase=struct('RandomBase',randomBase,'RandomPhase',randomPhase, ...
    'Multiplier',multiplier,'UsesRandomPhase',uses, ...
    'EventKey',eventKey,'EventKeyId',eventKeyId);
end
