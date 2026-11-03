function Science=BuildG4Seed1TrustedScienceObjects_v1(Pair,InputParams,RunIdentity,Contract)
% Internal post-traversal construction from this invocation's Pair only.
arguments
    Pair (1,1) struct
    InputParams (1,1) struct
    RunIdentity (1,1) struct
    Contract (1,1) struct
end
fs=double(InputParams.fs);n=numel(Pair.M2hSca);
[m2p,m2m,m2a]=sideHLocal(Pair.M2Events,fs,n);
[m0p,m0m,m0a]=sideHLocal(Pair.M0CEvents,fs,n);
RawM2=struct('hTotal',Pair.M2hSca(:),'hPlus',m2p,'hMinus',m2m,'hAxis',m2a,'Tolerance',4e-14);
RawM0C=struct('hTotal',Pair.M0ChSca(:),'hPlus',m0p,'hMinus',m0m,'hAxis',m0a,'Tolerance',4e-14);
spreadTime=0;if isfield(InputParams,'SpreadTime'),spreadTime=InputParams.SpreadTime;end
[d0,s0]=ApplyTimeSmearing(Pair.M0ChSca,Pair.CommonhDir,spreadTime,InputParams);
[d2,s2]=ApplyTimeSmearing(Pair.M2hSca,Pair.CommonhDir,spreadTime,InputParams);
z0=d0(:)+s0(:);z2=d2(:)+s2(:);
[M0,E0,P0]=ComputePaperResponseMetrics20ms_v2(z0,fs,0,60,"M0-C");
[M2,E2,P2]=ComputePaperResponseMetrics20ms_v2(z2,fs,0,60,"M2");
[ObsM0C,ObsAudit0]=ApplyPaperObservation20msToSideResponses(RawM0C.hTotal,RawM0C.hPlus,RawM0C.hMinus,RawM0C.hAxis,fs);
[ObsM2,ObsAudit2]=ApplyPaperObservation20msToSideResponses(RawM2.hTotal,RawM2.hPlus,RawM2.hMinus,RawM2.hAxis,fs);
side0=ComputePaperMirrorMetrics20ms(ObsM0C.zPlus,ObsM0C.zMinus,RawM0C.hPlus,RawM0C.hMinus,fs);
side2=ComputePaperMirrorMetrics20ms(ObsM2.zPlus,ObsM2.zMinus,RawM2.hPlus,RawM2.hMinus,fs);
native=BuildG4NativeMetricTable_v1(M0,M2);
metricAudit=ValidateG4NativeMetricPipeline_v1(native,string(Contract.Dnum.Path),string(Contract.Dnum.SHA256));
dnum=readtable(string(Contract.Dnum.Path),'FileType','text','Delimiter',',','TextType','string','VariableNamingRule','preserve','Encoding','UTF-8');
out=repmat(struct(),10,1);
if metricAudit.AllPass
    for k=1:10
        mct=mctLocal(native.MetricClass(k),Contract.MCT);
        out(k)=EvaluateG4ScalarD1MCT_v2(native.Q_M0C(k),native.Q_M2(k),double(dnum.D_num(k)),native.MetricClass(k),native.StructuralPrerequisite(k),mct);
    end
end
if isempty(fieldnames(out(1))),classified=table();else,classified=struct2table(out);classified.QoI=native.QoI;end
mv=BuildG4ModelVectorProspective_v1(double(E0.RMSAmplitude),double(E2.RMSAmplitude),"NORMALIZE_EACH_THEN_DIFFERENCE");
controls=LoadG4FrozenControlVectors_v1(Contract.NumericalVectorSources);
projection=ProjectG4NumericalSubspaceThinQR_v1(controls.V,mv.v_model);
geometry=ComputeG4ContinuousVectorGeometry_v1(mv.v_model,controls.V,controls.iC5);
Observed=struct('zTotal',ObsM2.zTotal(:),'zPlus',ObsM2.zPlus(:),'zMinus',ObsM2.zMinus(:), ...
    'zAxis',ObsM2.zAxis(:),'Tolerance',4e-14,'ObserverIdentity',"P20_20MS_EXACTLY_ONCE", ...
    'M0C',ObsM0C,'M2',ObsM2,'AuditM0C',ObsAudit0,'AuditM2',ObsAudit2,'PrimaryZ_M0C',z0,'PrimaryZ_M2',z2);
Side=struct('abs_A_E',abs(side2.A_E),'D_pm',side2.D_pm,'signed_A_E',side2.A_E,'C_pm',side2.C_pm, ...
    'M0C',side0,'M2',side2);
Envelope=struct('NormalizedM0C',mv.NormalizedM0C,'NormalizedM2',mv.NormalizedM2,'v_model',mv.v_model, ...
    'OperationOrder',mv.OperationOrder,'DirectionState',mv.DirectionState,'Projection',projection,'Geometry',geometry,'TimeS',double(E0.TimeS));
Science=struct('RunIdentity',RunIdentity,'Pair',Pair,'RawResponses',RawM2,'RawM0C',RawM0C, ...
    'ObservedResponses',Observed,'M0CMetrics',M0,'M2Metrics',M2,'M0CPeaks',P0,'M2Peaks',P2, ...
    'NativeMetricTable',native,'MetricPipeline',metricAudit,'D1MCTOutputs',classified, ...
    'SideMetricOutputs',Side,'EnvelopeOutputs',Envelope,'ControlAuthority',controls.SourceAuthority);
end
function [hp,hm,ha]=sideHLocal(events,fs,n)
y=double([events.Y]);hp=BuildImpulseResponseFromEvents(events(y>0),fs,n);hm=BuildImpulseResponseFromEvents(events(y<0),fs,n);ha=BuildImpulseResponseFromEvents(events(y==0),fs,n);hp=hp(:);hm=hm(:);ha=ha(:);
end
function value=mctLocal(cls,M)
if cls=="POSITIVE_RELATIVE_LINEAR",value=M.POSITIVE_RELATIVE_LINEAR;elseif cls=="DB_NATIVE",value=M.DB_NATIVE;else,value=M.TIMING_NATIVE;end
end
