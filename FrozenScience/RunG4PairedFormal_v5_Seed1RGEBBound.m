function Result=RunG4PairedFormal_v5_Seed1RGEBBound(Request)
% Seed-1 runner with internal real-output evidence, durable ledger, and RAAB.
arguments
    Request (1,1) struct
end
rejectCallerEvidenceLocal(Request);
here=fileparts(mfilename('fullpath'));stageRoot=fileparts(here);
contractPath=fullfile(stageRoot,'Config','G4_Seed1_ScienceAuthorizationContract_v3.json');
registryPath=fullfile(stageRoot,'Config','G4_Seed1_AuthorizationRuntimeRegistry_v3.csv');
Contract=jsondecode(fileread(contractPath));mode=string(fieldLocal(Request,'Mode',"inspect_contract"));
if mode=="inspect_contract"
    Result=struct('RunnerVersion',"G4_SEED1_RGEB_RUNNER_v5",'ScientificExecutionAuthorized',false, ...
        'RealResearcherAuthorizationArtifact',"NOT_ISSUED",'G4_RESULT_COUNT',0,'Seed1Run',false, ...
        'v_model',"NOT_GENERATED",'G4_SCIENTIFIC_EXECUTION',"NOT_AUTHORIZED",'G5',"LOCKED");return
end
assert(any(mode==["authorization_boundary_dry_run","scientific_execution"]),'G4Seed1RGEB:UnsupportedMode','Unsupported runner mode.');
assert(double(fieldLocal(Request,'RosterIndex',NaN))==1,'G4Seed1Auth:UnauthorizedRosterIndex','Only roster index 1 is eligible.');

artifactPath=string(fieldLocal(Request,'AuthorizationArtifactPath',""));
artifactSHA=string(fieldLocal(Request,'AuthorizationArtifactSHA256',""));
bindings=struct('Seed',262709171,'PayloadSHA256',string(Contract.Seed1.PayloadSHA256),'RandomModelVersion',1, ...
    'ScienceRunnerSHA256',sha256FileLocal(string(which(mfilename))), ...
    'AuthorizationContractSHA256',sha256FileLocal(string(contractPath)), ...
    'RuntimeRegistrySHA256',sha256FileLocal(string(registryPath)), ...
    'FrozenDnumSHA256',string(Contract.Dnum.SHA256), ...
    'NumericalGeometryContractSHA256',string(Contract.NumericalGeometryContractSHA256));
allowFixture=mode=="authorization_boundary_dry_run";
artifactAudit=ValidateG4Seed1AuthorizationArtifact_v1(artifactPath,artifactSHA,bindings,allowFixture);

preStem=string(fieldLocal(Request,'PreRARCOutputStem',fullfile(stageRoot,'Logs','FutureSeed1_PRE_RARC')));
PreRARC=ResolveG4RuntimeAuthorityClosure_v1(string(registryPath),preStem,"PRE_TRAVERSAL");
ValidateG4Seed1Identity_v1(Request,Contract);
if allowFixture
    ledgerPath=string(fieldLocal(Request,'LedgerPath',Contract.DSAL.LedgerPath));
    ledgerSHA=string(fieldLocal(Request,'LedgerExpectedSHA256',sha256FileLocal(ledgerPath)));
else
    ledgerPath=string(Contract.DSAL.LedgerPath);ledgerSHA=string(Contract.DSAL.InitialLedgerSHA256);
end
UpdateG4Seed1AcceptanceLedger_v1(ledgerPath,ledgerSHA,"ASSERT_RUNNABLE",struct());
if allowFixture
    Result=struct('State',"TRAVERSAL_BOUNDARY_REACHED_NOT_EXECUTED",'AuthorizationArtifactAudit',artifactAudit, ...
        'PreRARC',PreRARC,'ScientificExecutionAuthorized',false,'M2TraversalCount',0,'RandomDrawCount',0, ...
        'ScientificWaveformCount',0,'G4_RESULT_COUNT',0,'Seed1Run',false,'v_model',"NOT_GENERATED");return
end
assert(artifactAudit.TraversalAuthorization,'G4Seed1AuthArtifact:NotAuthorized','Synthetic artifact cannot authorize traversal.');

RunIdentity=struct('ScientificRunId',string(char(java.util.UUID.randomUUID())),'RosterIndex',1, ...
    'Seed',double(Request.Seed),'PayloadSHA256',string(Request.SeedPayloadSHA256), ...
    'RandomModelVersion',double(Request.RandomModelVersion));
budget=EnforceG4SeedAtomicExecutionUnit_v1(0,0,"INITIALIZE");
executionContract=executionContractLocal(Contract,registryPath);
assertProductionContractLocal(Request.InputParams,Contract);
Pair=BuildG4PairedResponsesSingleTraversal_v1(Request.InputParams,string(Request.TempWorkDir), ...
    executionContract,string(Request.PairingManifestStem));
budget=EnforceG4SeedAtomicExecutionUnit_v1(budget.TraversalCount,budget.RandomDrawCount,"REGISTER_SINGLE_TRAVERSAL");
Science=BuildG4Seed1TrustedScienceObjects_v1(Pair,Request.InputParams,RunIdentity,Contract);
postStem=string(fieldLocal(Request,'PostRARCOutputStem',fullfile(stageRoot,'Logs','FutureSeed1_POST_RARC')));
PostRARC=ResolveG4RuntimeAuthorityClosure_v1(string(registryPath),postStem,"POST_GENERATION");
[RetentionManifest,Retention]=PersistG4Seed1GeneratedObjects_v1(Science,PreRARC,PostRARC,string(Request.ScientificOutputRoot));
[~,generatedLedgerSHA]=UpdateG4Seed1AcceptanceLedger_v1(ledgerPath,ledgerSHA,"MARK_GENERATED",RunIdentity);
Context=struct('RunIdentity',RunIdentity,'PreRARC',PreRARC,'PostRARC',PostRARC,'Pair',Pair, ...
    'RawResponses',Science.RawResponses,'ObservedResponses',Science.ObservedResponses, ...
    'MetricPipeline',Science.MetricPipeline,'D1MCTOutputs',Science.D1MCTOutputs, ...
    'SideMetricOutputs',Science.SideMetricOutputs, ...
    'EnvelopeOutputs',Science.EnvelopeOutputs,'Retention',Retention,'SourceObjects',RetentionManifest);
Evidence=BuildG4Seed1RealGateEvidence_v1(Context);
acceptancePath=fullfile(Request.ScientificOutputRoot,'Seed1AcceptanceManifest.json');
Result=FinalizeG4Seed1Acceptance_v2(Evidence,string(registryPath),ledgerPath,generatedLedgerSHA,acceptancePath);
Result.Seed1Run=true;Result.ScientificRunId=RunIdentity.ScientificRunId;Result.AtomicBudget=budget;
end
function rejectCallerEvidenceLocal(S)
names={'FutureGateEvidence','RuntimeIntegrity','PairingIntegrity','RealizationIdentity','ObserverIntegrity','MetricPipelineIntegrity','D1MCTPolicyCompliance'};
for k=1:numel(names),assert(~isfield(S,names{k}),'G4Seed1RGEB:CallerSuppliedGateEvidenceProhibited','Caller-supplied acceptance evidence is prohibited.');end
end
function C=executionContractLocal(Contract,registryPath)
T=readtable(registryPath,'FileType','text','Delimiter',',','TextType','string','VariableNamingRule','preserve','Encoding','UTF-8');S=struct();
for k=1:height(T),S.(matlab.lang.makeValidName(char(T.FunctionName(k))))=char(T.ExpectedSHA256(k));end
C=struct('G4ScientificExecutionAuthorized',true,'RandomModelVersion',double(Contract.Seed1.RandomModelVersion),'ActiveSourceSHAs',S);
end
function assertProductionContractLocal(P,C)
assert(double(P.fs)==double(C.ProductionContract.FormalFsHz),'G4Seed1RGEB:FormalFsMismatch');
assert(double(P.Itg)==double(C.ProductionContract.P20S),'G4Seed1RGEB:P20Mismatch');
assert(double(P.DomainResolved.RmaxM)==double(C.ProductionContract.RmaxM),'G4Seed1RGEB:RmaxMismatch');
end
function v=fieldLocal(S,n,d),if isfield(S,n),v=S.(n);else,v=d;end,end
function h=sha256FileLocal(path),assert(isfile(path),'G4Seed1RGEB:AuthorityMissing');fid=fopen(path,'rb');c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[])));end %#ok<NASGU>
