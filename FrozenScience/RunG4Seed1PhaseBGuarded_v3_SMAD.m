function Result=RunG4Seed1PhaseBGuarded_v3_SMAD(Request)
% SMAD 候选入口：仅 Evidence #4--#7；当前 authorization 仍未签发。
% 必须 fresh MATLAB -batch；InputParams MAT 及依赖清单必须由新授权精确绑定。
arguments
    Request (1,1) struct
end
stageRoot=string(fileparts(fileparts(mfilename('fullpath'))));
Result=struct('State','HOLD_FOR_RRB_REVIEW','ActualM2TraversalCount',0,'ActualRandomDrawCount',0, ...
    'G4_RESULT_COUNT',0,'Seed1Run',false,'G5','LOCKED');
if ~isfield(Request,'Mode') || string(Request.Mode)=="inspect_contract",return;end
assert(string(Request.Mode)=="phase_b_evidence_4_to_7",'G4PB:UnsupportedMode','G4PB:UnsupportedMode');
allowed={'Mode','AuthorizationArtifactPath','AuthorizationArtifactSHA256','OutputRoot'};
assert(all(ismember(fieldnames(Request),allowed)),'G4PB:CallerEvidenceOrInputOverride','G4PB:CallerEvidenceOrInputOverride');
assert(batchStartupOptionUsed,'G4PB:FreshBatchRequired','G4PB:FreshBatchRequired');
contractPath=fullfile(stageRoot,'Config','PhaseBPairedScenarioContract_v1.json');
registryPath=fullfile(stageRoot,'Config','PhaseBRuntimeRegistry_SMAD_v1.csv');
C=jsondecode(fileread(contractPath));old=jsondecode(fileread(C.FrozenContractPath));
bindings=struct('Seed',262709171,'PayloadSHA256',string(old.Seed1.PayloadSHA256),'RandomModelVersion',1, ...
    'ScienceRunnerSHA256',G4PhaseBIO_v1("HASH",string(which(mfilename))), ...
    'AuthorizationContractSHA256',G4PhaseBIO_v1("HASH",contractPath), ...
    'RuntimeRegistrySHA256',G4PhaseBIO_v1("HASH",registryPath), ...
    'FrozenDnumSHA256',string(old.Dnum.SHA256),'NumericalGeometryContractSHA256',string(old.NumericalGeometryContractSHA256));
A=jsondecode(fileread(Request.AuthorizationArtifactPath));
% 此检查先于旧通用验证器，确保旧 ID 无论其 scope 写法如何均硬拒绝。
assert(string(A.AuthorizationId)~=string(C.SupersededAuthorizationId),'G4PB:RRBRequiredOldAuthorization','G4PB:RRBRequiredOldAuthorization');
audit=ValidateG4Seed1AuthorizationArtifact_v1(string(Request.AuthorizationArtifactPath), ...
    string(Request.AuthorizationArtifactSHA256),bindings,false);
assert(audit.TraversalAuthorization && string(A.ArtifactState)=="ISSUED_SHA_BOUND" ...
    && A.CurrentTaskTraversalAuthorized && A.ScientificExecutionAuthorized ...
    && string(A.CurrentTask)=="APID_PHASE_B_EVIDENCE_4_TO_7_ONLY",'G4PB:StageNotAuthorized','G4PB:StageNotAuthorized');
assert(A.RRBReviewApproved && strlength(string(A.RRBReviewPath))>0,'G4PB:RRBReviewMissing','G4PB:RRBReviewMissing');
verifyFile(A.RRBReviewPath,A.RRBReviewSHA256);
review=jsondecode(fileread(A.RRBReviewPath));
assert(review.Approved && string(review.ScienceRunnerSHA256)==bindings.ScienceRunnerSHA256 ...
    && string(review.RuntimeRegistrySHA256)==bindings.RuntimeRegistrySHA256 ...
    && string(review.AuthorizationContractSHA256)==bindings.AuthorizationContractSHA256,'G4PB:RRBReviewBinding','G4PB:RRBReviewBinding');
assert(string(A.ScienceRunnerPath)==string(which(mfilename)) ...
    && string(A.AuthorizationContractPath)==contractPath ...
    && string(A.RuntimeRegistryPath)==registryPath,'G4PB:AuthorityPathMismatch','G4PB:AuthorityPathMismatch');
verifyFile(C.FrozenContractPath,C.FrozenContractSHA256);
verifyFile(C.RosterPath,C.RosterSHA256);verifyFile(C.RosterSpecPath,C.RosterSpecSHA256);
verifyFile(C.FrozenDnumPath,C.FrozenDnumSHA256);verifyFile(C.GeometryPath,C.GeometrySHA256);
verifyFile(A.ProductionInputPath,A.ProductionInputSHA256);
assert(review.ProductionInputSHA256==string(A.ProductionInputSHA256) && review.ProductionContractReviewed, ...
    'G4PB:ProductionInputNotReviewed','Exact production input lacks completed review.');
verifyFile(A.ProductionInputAuditPath,A.ProductionInputAuditSHA256);
assert(string(review.ProductionInputAuditSHA256)==string(A.ProductionInputAuditSHA256), ...
    'G4PB:ProductionInputAuditBinding','G4PB:ProductionInputAuditBinding');
inputAudit=jsondecode(fileread(A.ProductionInputAuditPath));
assert(inputAudit.AllRowsPass && inputAudit.RowCount>=12 && ...
    inputAudit.PairedScenarioValidationAllPass && ...
    inputAudit.DualResolutionEquivalencePass && ~inputAudit.C1_TO_C6_RERUN_REQUIRED, ...
    'G4PB:ProductionInputAuditFailed','Row-wise production-input audit is not closed.');
% 全部外部输入依赖（BELLHOP/环境等）须在审核清单中冻结。空清单硬拒绝。
verifyFile(A.ProductionDependenciesPath,A.ProductionDependenciesSHA256);
assert(string(review.ProductionDependenciesSHA256)==string(A.ProductionDependenciesSHA256),'G4PB:DependencyReviewBinding','G4PB:DependencyReviewBinding');
dependencies=jsondecode(fileread(A.ProductionDependenciesPath));
assert(~isempty(dependencies),'G4PB:EmptyProductionDependencies','G4PB:EmptyProductionDependencies');
for k=1:numel(dependencies),G4PhaseBIO_v1("VERIFY","",dependencies(k));end
bellhopLauncher=string({dependencies(contains(string({dependencies.Role}),'Active BELLHOP MATLAB launcher')).Path});
bellhopExecutable=string({dependencies(contains(string({dependencies.Role}),'Active BELLHOP executable')).Path});
assert(isscalar(bellhopLauncher)&&isscalar(bellhopExecutable) ...
    && sameCanonicalPathLocal(string(which('bellhop')),bellhopLauncher) ...
    && sameCanonicalPathLocal(string(which('bellhop.exe')),bellhopExecutable), ...
    'G4PB:BellhopResolutionMismatch','Active BELLHOP launcher/executable is not the reviewed dependency.');
out=string(Request.OutputRoot);assert(~isfolder(out),'G4PB:OutputReuseProhibited','G4PB:OutputReuseProhibited');mkdir(out);
assert(isfield(review,'MinimumCaptureFreeBytes') && review.MinimumCaptureFreeBytes>0, ...
    'G4PB:StorageBudgetNotReviewed','Review must specify a raw capture storage budget.');
drive=System.IO.DriveInfo(System.IO.Path.GetPathRoot(char(out)));
assert(double(drive.AvailableFreeSpace)>=double(review.MinimumCaptureFreeBytes), ...
    'G4PB:InsufficientCaptureStorage','Insufficient free storage for reviewed raw capture budget.');
G4PhaseBIO_v1("JSON",fullfile(out,'StorageWriteProbe.json'),struct('UTC',char(datetime('now','TimeZone','UTC')), ...
    'AvailableFreeBytes',double(drive.AvailableFreeSpace),'RequiredFreeBytes',review.MinimumCaptureFreeBytes));
% 在唯一执行进程内部重新 PRE-RARC；不复用 Phase A receipt。
pre=ResolveG4RuntimeAuthorityClosure_v1(registryPath,fullfile(out,'Final_PRE_RARC'),"PRE_TRAVERSAL");
identityRequest=struct('RosterIndex',1,'Seed',uint32(262709171),'SeedPayload',old.Seed1.Payload, ...
    'SeedPayloadSHA256',old.Seed1.PayloadSHA256,'RandomModelVersion',1);
seedAudit=ValidateG4Seed1Identity_v1(identityRequest,old);
roster=readtable(C.RosterPath,'TextType','string','VariableNamingRule','preserve');
assert(height(roster)==20 && roster.r(1)==1 && roster.Seed(1)==262709171 ...
    && roster.SHA256Hex(1)==string(old.Seed1.PayloadSHA256) && roster.RandomModelVersion(1)==1,'G4PB:RosterMismatch','G4PB:RosterMismatch');
verifyFile(C.DSALPath,C.DSALInitialSHA256);
L=jsondecode(fileread(C.DSALPath));assert(string(L.State)=="NOT_RUN" && L.G4_RESULT_COUNT==0,'G4PB:DSALNotNotRun','G4PB:DSALNotNotRun');
assert(~isfile(C.LockPath),'G4ETL:ExistingLock','G4ETL:ExistingLock');
loaded=load(A.ProductionInputPath,'InputParams');P=loaded.InputParams;
pairedAuthorityPath=fullfile(stageRoot,'Config','G4PairedScenarioAuthority_v1.json');
verifyFile(pairedAuthorityPath,A.PairedScenarioAuthoritySHA256);
assert(string(review.PairedScenarioAuthoritySHA256)==string(A.PairedScenarioAuthoritySHA256) && ...
    string(review.ScenarioIdBranchAuditSHA256)==string(A.ScenarioIdBranchAuditSHA256) && ...
    string(review.DualResolutionEquivalenceAuditSHA256)==string(A.DualResolutionEquivalenceAuditSHA256), ...
    'G4SMAD:RRBAuthorityBinding','Paired-scenario RRB authority binding mismatch.');
verifyFile(A.ScenarioIdBranchAuditPath,A.ScenarioIdBranchAuditSHA256);
verifyFile(A.DualResolutionEquivalenceAuditPath,A.DualResolutionEquivalenceAuditSHA256);
resolvedAuthority=ResolveG4PairedScenarioAuthority_v1(P,pairedAuthorityPath);
pairedValidation=ValidateG4PairedProductionScenario_v1(P,resolvedAuthority,true);
assert(pairedValidation.AllPass && string(P.ScenarioId)=="S0-D-G4-Paired-v1" && ...
    string(P.ExecutionScenarioId)=="S0-D-G4-Paired-v1" && string(P.ParentScenarioId)=="S0-D-v1", ...
    'G4SMAD:ExecutionScenarioIdentity','Authorized paired-scenario input is invalid.');
assert(P.fs==old.ProductionContract.FormalFsHz && P.Itg==old.ProductionContract.P20S ...
    && P.DomainResolved.RmaxM==old.ProductionContract.RmaxM,'G4PB:ProductionContractMismatch','G4PB:ProductionContractMismatch');
assert(P.DomainResolved.GridI==30 && P.DomainResolved.GridIPlusM==100 ...
    && P.DomainResolved.BellhopLaunchAngleStepDeg==old.ProductionContract.LaunchAngleSpacingDeg ...
    && P.TWindow==60.2 && P.FormalAnalysisWindowS==60, ...
    'G4PB:ProductionContractMismatch','G4PB:ProductionContractMismatch');
assert(isa(P.ScatterGrid.RandomSeed,'uint32') && P.ScatterGrid.RandomSeed==uint32(262709171), ...
    'G4PB:ProductionSeedMismatch','Input seed must be exact uint32 roster Seed 1.');
id=struct('ScientificRunId',char(java.util.UUID.randomUUID()),'RosterIndex',1,'Seed',262709171, ...
    'SeedPayloadSHA256',old.Seed1.PayloadSHA256,'RandomModelVersion',1, ...
    'AuthorizationArtifactSHA256',char(audit.ArtifactSHA256), ...
    'ScienceRunnerSHA256',char(bindings.ScienceRunnerSHA256),'ContractSHA256',char(bindings.AuthorizationContractSHA256), ...
    'PID',feature('getpid'),'Host',char(System.Environment.MachineName), ...
    'MATLABVersion',version,'CreatedUTC',char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSSXXX")), ...
    'DSALPath',C.DSALPath);
token=G4ExclusiveTraversalLock_v1("ACQUIRE",string(C.LockPath),id);
ctx=struct('Root',out,'Identity',id,'LockPath',string(C.LockPath),'LockToken',token,'LedgerSHA256',string(C.DSALInitialSHA256));
try
    G4ExclusiveTraversalLock_v1("VERIFY",ctx.LockPath,id,token);
    G4PhaseBJournal_v1(out,id,"PREPARED",struct('M2TraversalCount',0,'RandomDrawCount',0));
    % 缩小 TOCTOU：锁内再次检查 DSAL/输入/authority；不允许重新调用 traversal。
    verifyFile(C.DSALPath,C.DSALInitialSHA256);verifyFile(A.ProductionInputPath,A.ProductionInputSHA256);
    verifyFile(Request.AuthorizationArtifactPath,Request.AuthorizationArtifactSHA256);
    finalPre=ResolveG4RuntimeAuthorityClosure_v1(registryPath,fullfile(out,'Locked_PRE_RARC'),"LOCKED_PRE_TRAVERSAL");
    t=readtable(registryPath,'TextType','string','VariableNamingRule','preserve');sources=struct();
    for k=1:height(t),sources.(char(t.FunctionName(k)))=char(t.ExpectedSHA256(k));end
    execContract=struct('G4ScientificExecutionAuthorized',true,'RandomModelVersion',1,'ActiveSourceSHAs',sources);
    G4PhaseBIO_v1("JSON",fullfile(out,'Evidence1to3_Revalidation.json'), ...
        struct('Identity',id,'Authorization',audit,'PreRARC',pre,'LockedPreRARC',finalPre,'Seed',seedAudit));
    temp=fullfile(out,'TraversalWork');mkdir(temp);
    pair=BuildG4PairedResponsesSingleTraversal_v4_SMAD_SideCapture(P,temp,execContract,ctx);
    ResolveG4RuntimeAuthorityClosure_v1(registryPath,fullfile(out,'POST_RARC'),"POST_PHASE_B");
    receipt=SealG4PhaseBAttempt_v1(ctx,true);
    G4ExclusiveTraversalLock_v1("RELEASE",ctx.LockPath,id,token,receipt);
    Result=struct('State','ACTUAL_PAIRING_PASS_FOR_SEED_1_PHASE_B','ScientificRunId',id.ScientificRunId, ...
        'Counts',pair.Counts,'OutcomeReceipt',receipt,'G4_RESULT_COUNT',0,'Seed1Run',true,'G5','LOCKED');
catch ME
    failure=struct('Identifier',ME.identifier,'Message',ME.message,'Stack',ME.stack);
    try
        if ~isfile(fullfile(out,'DurableOutcomeReceipt.json'))
            receipt=SealG4PhaseBAttempt_v1(ctx,false,failure);
            G4ExclusiveTraversalLock_v1("RELEASE",ctx.LockPath,id,token,receipt);
        end
    catch sealError
        warning('G4PB:FailureNotClosed','%s; lock retained; RRB recovery required.',sealError.message);
    end
    rethrow(ME);
end
end
function verifyFile(path,expected)
assert(isfile(path) && G4PhaseBIO_v1("HASH",string(path))==string(expected),'G4PB:FrozenArtifactMismatch','G4PB:FrozenArtifactMismatch');
end
function tf=sameCanonicalPathLocal(a,b)
tf=false;if strlength(a)==0||strlength(b)==0,return;end
tf=strcmpi(string(char(java.io.File(char(a)).getCanonicalPath())), ...
    string(char(java.io.File(char(b)).getCanonicalPath())));
end
