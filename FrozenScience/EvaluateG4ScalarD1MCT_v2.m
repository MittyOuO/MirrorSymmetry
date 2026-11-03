function Out=EvaluateG4ScalarD1MCT_v2(Q0,Q2,Dnum,MetricClass,StructuralPrerequisite,MCT)
% V2 adds fail-closed native finiteness before any scientific comparator.
arguments
    Q0 (1,1) double
    Q2 (1,1) double
    Dnum (1,1) double
    MetricClass (1,1) string
    StructuralPrerequisite (1,1) logical = true
    MCT (1,1) double = 0
end
assert(isfinite(Dnum)&&Dnum>0,'G4Seed1Metric:InvalidDnum','Dnum must be finite and positive.');
assert(isfinite(MCT)&&MCT>=0,'G4Seed1Metric:InvalidMCT','MCT must be finite and nonnegative.');
Out=struct('Q_M0C',Q0,'Q_M2',Q2,'SignedNativeDifference',Q2-Q0, ...
    'MetricClass',MetricClass,'Dnum',Dnum,'D1Valid',true,'RelativeDifference',NaN, ...
    'R_model',NaN,'RatioState',"CLASSIFIABLE",'ComparatorDelta',NaN, ...
    'MCT',MCT,'Classification',"NOT_EVALUATED",'LegalSpecialOutcome',false, ...
    'RetainSeed',true,'ReplaceSeed',false,'ExtendN',false);
assert(isfinite(Q2),'G4Seed1Metric:NativeNonfinite','Q_M2 must be finite for every scalar QoI.');
if MetricClass=="POSITIVE_RELATIVE_LINEAR"
    assert(~isfinite(Q0)||Q0>=0,'G4Seed1Metric:NativeDomainInvalid','Positive metric Q_M0C cannot be negative.');
    Out.D1Valid=isfinite(Q0)&&Q0>0&&StructuralPrerequisite;
    if ~Out.D1Valid
        Out.RatioState="RATIO_INVALID_NOT_CLASSIFIABLE";
        Out.R_model=NaN;Out.Classification="RATIO_INVALID_NOT_CLASSIFIABLE";
        Out.LegalSpecialOutcome=true;return
    end
    Out.RelativeDifference=(Q2-Q0)/Q0;
    Out.ComparatorDelta=abs(Out.RelativeDifference)-Dnum;
    Out.R_model=abs(Out.RelativeDifference)/Dnum;
elseif any(MetricClass==["DB_NATIVE","TIMING_NATIVE"])
    assert(isfinite(Q0),'G4Seed1Metric:NativeNonfinite','Q_M0C must be finite for a non-relative metric.');
    Out.ComparatorDelta=abs(Q2-Q0)-Dnum;
    Out.R_model=abs(Q2-Q0)/Dnum;
else
    error('G4Seed1Metric:WrongMetricClass','Unsupported scalar metric class.');
end
assert(isfinite(Out.ComparatorDelta),'G4Seed1Metric:ComparatorDeltaNonfinite', ...
    'ComparatorDelta must be finite before classification.');
if abs(Out.ComparatorDelta)<=MCT
    Out.Classification="MACHINE_BOUNDARY_INDETERMINATE";Out.LegalSpecialOutcome=true;
elseif Out.ComparatorDelta>0
    Out.Classification="ABOVE";
else
    Out.Classification="BELOW";
end
end
