function T=BuildG4NativeMetricTable_v1(M0C,M2)
% Trusted adapter from the two actual frozen P20 metric structs to 10 rows.
arguments
    M0C (1,1) struct
    M2 (1,1) struct
end
qoi=["WindowEnergy";"MeanRL";"P50RL";"P95RL";"t50";"t90"; ...
    "Peak prominence";"Fixed-neighborhood peak energy";"Major-peak timing";"Major-peak amplitude"];
field=["WindowEnergy";"MeanRLdB";"P50RLdB";"P95RLdB";"t50S";"t90S"; ...
    "MeanTopKPeakProminence";"SumTopKNeighborhoodEnergy";"MajorPeakTimeS";"MajorPeakRMSAmplitude"];
cls=["POSITIVE_RELATIVE_LINEAR";"DB_NATIVE";"DB_NATIVE";"DB_NATIVE";"TIMING_NATIVE";"TIMING_NATIVE"; ...
    "POSITIVE_RELATIVE_LINEAR";"POSITIVE_RELATIVE_LINEAR";"TIMING_NATIVE";"POSITIVE_RELATIVE_LINEAR"];
q0=zeros(10,1);q2=zeros(10,1);
for k=1:10
    assert(isfield(M0C,field(k))&&isfield(M2,field(k)),'G4Seed1Metric:MissingNativeField', ...
        'Actual metric helper output is missing %s.',field(k));
    q0(k)=double(M0C.(field(k)));q2(k)=double(M2.(field(k)));
end
structural=true(10,1);
if isfield(M0C,'TopKPeakCount')&&isfield(M2,'TopKPeakCount')
    structural(7:10)=double(M0C.TopKPeakCount)>0&&double(M2.TopKPeakCount)>0;
end
MCTClass=cls;
T=table(qoi,cls,MCTClass,q0,q2,structural,'VariableNames', ...
    {'QoI','MetricClass','MCTClass','Q_M0C','Q_M2','StructuralPrerequisite'});
end
