function Out=BuildG4ModelVectorProspective_v1(EnvelopeM0C,EnvelopeM2,OperationOrder)
% Prospective MVCC only: independently normalize each 6000-vector, then subtract.
arguments
    EnvelopeM0C (:,1) double
    EnvelopeM2 (:,1) double
    OperationOrder (1,1) string = "NORMALIZE_EACH_THEN_DIFFERENCE"
end
assert(OperationOrder=="NORMALIZE_EACH_THEN_DIFFERENCE", ...
    'G4Seed1Auth:MVCCOperationOrder','Difference-then-normalize is prohibited.');
assert(numel(EnvelopeM0C)==numel(EnvelopeM2),'G4Seed1Auth:MVCCLengthMismatch','Envelope lengths differ.');
assert(numel(EnvelopeM0C)==6000,'G4Seed1Auth:MVCCFrozenLength','Frozen envelope vectors require N=6000.');
assert(all(isfinite(EnvelopeM0C)) && all(isfinite(EnvelopeM2)), ...
    'G4Seed1Auth:MVCCNonfinite','Envelope vectors must be finite.');
n0=norm(EnvelopeM0C);n2=norm(EnvelopeM2);
assert(n0>0 && n2>0,'G4Seed1Auth:MVCCZeroEnvelope','Each source envelope must have positive norm.');
e0=EnvelopeM0C/n0;e2=EnvelopeM2/n2;v=e2-e0;mag=norm(v);
if mag==0
    direction="DIRECTION_UNDEFINED_ZERO_VECTOR";
else
    direction="DEFINED_CONTINUOUS_GEOMETRY";
end
Out=struct('NormalizedM0C',e0,'NormalizedM2',e2,'v_model',v, ...
    'Magnitude',mag,'DirectionState',direction,'OperationOrder',OperationOrder);
end
