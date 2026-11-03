function Evidence=BuildG4Seed1RealGateEvidence_v1(Context)
% Build sealed acceptance evidence only from actual source-bound run objects.
arguments
    Context (1,1) struct
end
forbidden={'FutureGateEvidence','RuntimeIntegrity','PairingIntegrity','RealizationIdentity', ...
    'ObserverIntegrity','MetricPipelineIntegrity','D1MCTPolicyCompliance'};
for k=1:numel(forbidden)
    assert(~isfield(Context,forbidden{k}),'G4Seed1RGEB:CallerSuppliedGateEvidenceProhibited', ...
        'Caller-style acceptance field is prohibited: %s.',forbidden{k});
end
required={'RunIdentity','PreRARC','PostRARC','Pair','RawResponses','ObservedResponses', ...
    'MetricPipeline','D1MCTOutputs','SideMetricOutputs','EnvelopeOutputs','Retention','SourceObjects'};
for k=1:numel(required),assert(isfield(Context,required{k}),'G4Seed1RGEB:SourceObjectMissing','Missing actual context object %s.',required{k});end
R=Context.RunIdentity;validateRunIdentityLocal(R);
S=Context.SourceObjects;validateSourceObjectsLocal(S,R);
sourcePaths=strjoin(string(S.ObjectPath),' | ');sourceSHAs=strjoin(string(S.ObjectSHA256),' | ');
builderPath=string(which(mfilename));builderSHA=sha256FileLocal(builderPath);
utc=string(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSSXXX'));

rarc=CompareG4PrePostRARC_v1(Context.PreRARC,Context.PostRARC);
pm=Context.Pair.PairingManifest;
pairPlus=string(pm.PairingGateStatus)=="PASS"&&double(pm.MismatchCount)==0&&double(pm.CommonPlusCountM0C)==double(pm.CommonPlusCountM2)&&double(pm.CommonPlusExactMatchedCount)==double(pm.CommonPlusCountM0C);
pairAxis=string(pm.PairingGateStatus)=="PASS"&&double(pm.MismatchCount)==0&&double(pm.AxisCountM0C)==double(pm.AxisCountM2)&&double(pm.AxisExactMatchedCount)==double(pm.AxisCountM0C);
realization=isfield(Context.Pair,'SameTraversalEventTableAndH')&&logical(Context.Pair.SameTraversalEventTableAndH)&& ...
    isfield(Context.Pair,'SecondRandomDrawPossible')&&~logical(Context.Pair.SecondRandomDrawPossible);
raw=Context.RawResponses;obs=Context.ObservedResponses;
rawResidual=norm(raw.hTotal-(raw.hPlus+raw.hMinus+raw.hAxis))/max(1,norm(raw.hTotal));
obsResidual=norm(obs.zTotal-(obs.zPlus+obs.zMinus+obs.zAxis))/max(1,norm(obs.zTotal));
rawPass=isfinite(rawResidual)&&rawResidual<=double(raw.Tolerance);
obsPass=isfinite(obsResidual)&&obsResidual<=double(obs.Tolerance)&&string(obs.ObserverIdentity)=="P20_20MS_EXACTLY_ONCE";
metricPass=logical(Context.MetricPipeline.AllPass)&&double(Context.MetricPipeline.QoICount)==10;
d1=Context.D1MCTOutputs;allowed=["ABOVE","BELOW","MACHINE_BOUNDARY_INDETERMINATE","RATIO_INVALID_NOT_CLASSIFIABLE"];
d1Pass=istable(d1)&&height(d1)==10&&all(ismember(string(d1.Classification),allowed));
if d1Pass
    classified=string(d1.Classification)~="RATIO_INVALID_NOT_CLASSIFIABLE";
    d1Pass=all(isfinite(double(d1.ComparatorDelta(classified))))&&all(logical(d1.RetainSeed))&& ...
        all(~logical(d1.ReplaceSeed))&&all(~logical(d1.ExtendN));
end
side=Context.SideMetricOutputs;
sidePass=isstruct(side)&&~isfield(side,'R_model')&&all(isfinite([double(side.abs_A_E),double(side.D_pm),double(side.signed_A_E),double(side.C_pm)]));
env=Context.EnvelopeOutputs;
mvccPass=isfield(env,'v_model')&&numel(env.v_model)==6000&&string(env.OperationOrder)=="NORMALIZE_EACH_THEN_DIFFERENCE";
zvdgPass=mvccPass&&((norm(env.v_model)>0&&string(env.DirectionState)=="DEFINED_CONTINUOUS_GEOMETRY")|| ...
    (norm(env.v_model)==0&&string(env.DirectionState)=="DIRECTION_UNDEFINED_ZERO_VECTOR"));
projectorPass=isfield(env,'Projection')&&string(env.Projection.ProductionProjector)=="THIN_QR"&& ...
    double(env.Projection.RankQR)==4&&double(env.Projection.ClosureResidual)<=4e-14;
middPass=isfield(env,'Geometry')&&string(env.Geometry.MIDDIdentity)=="SECONDARY_CONTINUOUS_DIAGNOSTIC"&& ...
    string(env.Geometry.BinaryDirectionThreshold)=="PROHIBITED";
retentionPass=isfield(Context.Retention,'AllPass')&&logical(Context.Retention.AllPass)&&double(Context.Retention.RequiredClassCount)==12;
gateIds=["PRE_POST_RARC";"PAIR_POSITIVE";"PAIR_AXIS";"REALIZATION";"RAW_CLOSURE"; ...
    "OBSERVER_CLOSURE";"METRIC_PIPELINE";"D1_MCT";"SIDE_ROUTE";"MVCC";"ZVDG";"PROJECTOR";"MIDD";"RETENTION_COMPLETENESS"];
passes=[rarc.PASS;pairPlus;pairAxis;realization;rawPass;obsPass;metricPass;d1Pass;sidePass;mvccPass;zvdgPass;projectorPass;middPass;retentionPass];
legal=false(size(passes));
details=[rarc.Details;"mismatch="+string(pm.MismatchCount);"axisMatched="+string(pm.AxisExactMatchedCount); ...
    "sameTraversal="+string(realization);"relativeResidual="+string(rawResidual);"relativeResidual="+string(obsResidual); ...
    "QoICount="+string(Context.MetricPipeline.QoICount);"classifications="+strjoin(string(d1.Classification),','); ...
    "noSideScalarRmodel="+string(sidePass);"N="+string(numel(env.v_model));"direction="+string(env.DirectionState); ...
    "rank="+string(env.Projection.RankQR);"continuousNoThreshold="+string(middPass);"classes=12"];
rows=repmat(evidenceRowLocal(),numel(gateIds),1);
for k=1:numel(gateIds)
    failure="";if ~passes(k),failure="G4Seed1RGEB:"+gateIds(k)+"Failed";end
    rows(k)=struct('GateId',gateIds(k),'Pass',logical(passes(k)),'LegalSpecialOutcome',logical(legal(k)), ...
        'FailureIdentifier',failure,'SourceObjectPaths',sourcePaths,'SourceObjectSHA256',sourceSHAs, ...
        'SourceRunId',string(R.ScientificRunId),'RosterIndex',double(R.RosterIndex),'Seed',double(R.Seed), ...
        'PayloadSHA256',string(R.PayloadSHA256),'RandomModelVersion',double(R.RandomModelVersion), ...
        'EvaluationHelper',"BuildG4Seed1RealGateEvidence_v1",'EvaluationHelperSHA256',builderSHA, ...
        'EvaluationUTC',utc,'Details',details(k));
end
Evidence=struct('Version',"G4_SEED1_REAL_GATE_EVIDENCE_v1",'GeneratedInternally',true, ...
    'BuilderSHA256',builderSHA,'ScientificRunId',string(R.ScientificRunId), ...
    'RosterIndex',double(R.RosterIndex),'Seed',double(R.Seed),'PayloadSHA256',string(R.PayloadSHA256), ...
    'RandomModelVersion',double(R.RandomModelVersion),'SourceObjects',S,'GateRows',rows, ...
    'AllRequiredGatesPass',all(passes),'InternalSealSHA256',"");
Evidence.InternalSealSHA256=sealLocal(Evidence);
end
function r=evidenceRowLocal()
r=struct('GateId',"",'Pass',false,'LegalSpecialOutcome',false,'FailureIdentifier',"", ...
    'SourceObjectPaths',"",'SourceObjectSHA256',"",'SourceRunId',"",'RosterIndex',0,'Seed',0, ...
    'PayloadSHA256',"",'RandomModelVersion',0,'EvaluationHelper',"",'EvaluationHelperSHA256',"", ...
    'EvaluationUTC',"",'Details',"");
end
function validateRunIdentityLocal(R)
required={'ScientificRunId','RosterIndex','Seed','PayloadSHA256','RandomModelVersion'};
for k=1:numel(required),assert(isfield(R,required{k}),'G4Seed1RGEB:RunIdentityMissing','Run identity field missing.');end
assert(strlength(string(R.ScientificRunId))>0&&double(R.RosterIndex)==1&&double(R.Seed)==262709171&& ...
    double(R.RandomModelVersion)==1&&strlength(string(R.PayloadSHA256))==64, ...
    'G4Seed1RGEB:RunIdentityMismatch','Run identity is not exact Seed 1.');
end
function validateSourceObjectsLocal(T,R)
assert(istable(T),'G4Seed1RGEB:SourceObjectManifestInvalid','SourceObjects must be a table.');
required=["ObjectId","ObjectPath","ObjectBytes","ObjectSHA256","ScientificRunId","RosterIndex","Seed","PayloadSHA256","RandomModelVersion"];
assert(all(ismember(required,string(T.Properties.VariableNames)))&&height(T)>0,'G4Seed1RGEB:SourceObjectManifestInvalid','Source object manifest schema invalid.');
for k=1:height(T)
    assert(string(T.ScientificRunId(k))==string(R.ScientificRunId)&&double(T.RosterIndex(k))==1&& ...
        double(T.Seed(k))==double(R.Seed)&&strcmpi(string(T.PayloadSHA256(k)),string(R.PayloadSHA256))&& ...
        double(T.RandomModelVersion(k))==double(R.RandomModelVersion),'G4Seed1RGEB:RunIdentityMismatch','Mixed run identity detected.');
    p=string(T.ObjectPath(k));assert(isfile(p),'G4Seed1RGEB:SourceObjectMissing','Source object is missing.');d=dir(p);h=sha256FileLocal(p);
    assert(d.bytes==double(T.ObjectBytes(k))&&strcmpi(h,string(T.ObjectSHA256(k))), ...
        'G4Seed1RGEB:SourceObjectSHAMismatch','Source object SHA/bytes mismatch.');
end
end
function s=sealLocal(E)
E.InternalSealSHA256="";md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(uint8(unicode2native(jsonencode(E),'UTF-8'))),'uint8');s=string(lower(reshape(dec2hex(d,2).',1,[])));
end
function h=sha256FileLocal(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
