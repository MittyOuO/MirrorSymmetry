function [Resolved, Derived, Audit] = ResolveG3Parameters(InputParams, consumerProfile)
%ResolveG3Parameters Resolve all G3 parameters at one explicit boundary.

if nargin < 2 || isempty(consumerProfile), consumerProfile='single'; end
scatterProfile=consumerProfile;
if strcmpi(consumerProfile,'channels'), scatterProfile='event'; end
if strcmpi(consumerProfile,'single_direct'), scatterProfile='event'; end
[Scattering,scatterAudit]=ResolveBottomScattering(InputParams,scatterProfile);
[Domain,domainAudit]=ResolveBottomDomain(InputParams,consumerProfile);

Resolved=InputParams;
Resolved.ReleaseId='TH01-01-v2.1-G3RangeExplicit';
Resolved.ScatteringResolved=Scattering;
Resolved.DomainResolved=Domain;
Resolved.RmaxM=Domain.RmaxM;
Resolved.Rmax=Domain.RmaxM; % internal compatibility alias only
Resolved.ScatterGrid=struct('GridI',Domain.GridI,'GridIPlusM',Domain.GridIPlusM);

formalRmaxLowerBoundM=40000;
if isfield(InputParams,'FormalSimulationRmaxLowerBoundM') && ...
        ~isempty(InputParams.FormalSimulationRmaxLowerBoundM)
    formalRmaxLowerBoundM=positiveScalarLocal( ...
        InputParams.FormalSimulationRmaxLowerBoundM,'FormalSimulationRmaxLowerBoundM');
end
executionPurpose='';
if isfield(InputParams,'ExecutionPurpose') && ~isempty(InputParams.ExecutionPurpose)
    executionPurpose=lower(strtrim(char(string(InputParams.ExecutionPurpose))));
end
formalRequested=contains(executionPurpose,'formal');
if isfield(InputParams,'FormalSimulationEligible') && ...
        ~isempty(InputParams.FormalSimulationEligible)
    formalRequested=formalRequested || logicalScalarLocal( ...
        InputParams.FormalSimulationEligible,'FormalSimulationEligible');
end
if formalRequested && Domain.RmaxM<formalRmaxLowerBoundM
    error('G3:FormalRmaxBelowMinimum', ...
        'Formal simulation requires RmaxM >= %.9g m; received %.9g m.', ...
        formalRmaxLowerBoundM,Domain.RmaxM);
end
Resolved.FormalSimulationRmaxLowerBoundM=formalRmaxLowerBoundM;
Resolved.FormalSimulationEligible=formalRequested && Domain.RmaxM>=formalRmaxLowerBoundM;
Resolved.ExecutionPurpose=executionPurpose;
Resolved.FormalBellhopRangeStepM=1;
Resolved.FormalBellhopRangeStepIsConvergenceVariable=false;

if strcmp(Scattering.InputConvention,'canonical')
    if ~isfield(InputParams,'Fs') || isempty(InputParams.Fs)
        error('G3:MissingParameter','Canonical input requires InputParams.Fs.');
    end
    if ~isfield(InputParams,'TWindow') || isempty(InputParams.TWindow)
        error('G3:MissingParameter','Canonical input requires InputParams.TWindow.');
    end
    fs=positiveScalarLocal(InputParams.Fs,'Fs');
    tWindow=positiveScalarLocal(InputParams.TWindow,'TWindow');
else
    if isfield(InputParams,'fs') && ~isempty(InputParams.fs)
        fs=positiveScalarLocal(InputParams.fs,'fs');
    elseif isfield(InputParams,'Fs') && ~isempty(InputParams.Fs)
        fs=positiveScalarLocal(InputParams.Fs,'Fs');
    else
        error('G3:MissingParameter','Legacy input requires fs or Fs.');
    end
    if isfield(InputParams,'TWindowCompute') && ~isempty(InputParams.TWindowCompute)
        tWindow=positiveScalarLocal(InputParams.TWindowCompute,'TWindowCompute');
    elseif isfield(InputParams,'TWindow') && ~isempty(InputParams.TWindow)
        tWindow=positiveScalarLocal(InputParams.TWindow,'TWindow');
    else
        tWindow=50;
    end
end
Resolved.fs=fs; Resolved.Fs=fs; Resolved.TWindow=tWindow;

disablePhase=false;
if isfield(InputParams,'Model') && isstruct(InputParams.Model) && ...
        isfield(InputParams.Model,'DisableAdditionalRandomPhase') && ...
        ~isempty(InputParams.Model.DisableAdditionalRandomPhase)
    disablePhase=logicalScalarLocal(InputParams.Model.DisableAdditionalRandomPhase, ...
        'Model.DisableAdditionalRandomPhase');
end
scenarioId='';
if isfield(InputParams,'ScenarioId') && ~isempty(InputParams.ScenarioId)
    scenarioId=char(string(InputParams.ScenarioId));
end
if strcmp(Scattering.InputConvention,'canonical') && strcmp(scenarioId,'S0-D-v1') && ~disablePhase
    error('G3:S0DRequiresM1','S0-D-v1 requires Model.DisableAdditionalRandomPhase=true.');
end
Resolved.Model=fieldStructLocal(InputParams,'Model');
Resolved.Model.DisableAdditionalRandomPhase=disablePhase;

if strcmp(scenarioId,'S0-D-v1')
    assertOmnidirectionalLocal(InputParams);
end

Derived=Domain;
Audit=struct('ReleaseId','TH01-01-v2.1-G3RangeExplicit','ScenarioId',scenarioId, ...
    'InputConvention',Scattering.InputConvention, ...
    'PaperEligible',Scattering.PaperEligible,'ConsumerProfile',consumerProfile, ...
    'Scattering',scatterAudit,'Domain',domainAudit,'Fs',fs,'TWindow',tWindow, ...
    'DisableAdditionalRandomPhase',disablePhase, ...
    'ExecutionPurpose',executionPurpose, ...
    'FormalSimulationRmaxLowerBoundM',formalRmaxLowerBoundM, ...
    'FormalSimulationEligible',Resolved.FormalSimulationEligible, ...
    'FormalBellhopRangeStepM',1, ...
    'FormalBellhopRangeStepIsConvergenceVariable',false);
end

function assertOmnidirectionalLocal(P)
if ~isfield(P,'Beam') || ~isstruct(P.Beam), error('G3:S0DBeamMissing','S0-D-v1 requires Beam.'); end
B=P.Beam;
checks={fieldLocal(B,'AzimuthRange',[]),[-180 180],'AzimuthRange'; ...
    fieldLocal(B,'OpenAngle',[]),[90 -90],'OpenAngle'; ...
    fieldLocal(B,'MainBeam',[]),[90 -90],'MainBeam'};
for k=1:size(checks,1)
    if ~isequal(double(checks{k,1}(:).'),double(checks{k,2}))
        error('G3:S0DNotOmnidirectional','S0-D-v1 Beam.%s is not approved omnidirectional value.',checks{k,3});
    end
end
if ~isequal(double(fieldLocal(B,'SideDown_dB',NaN)),0)
    error('G3:S0DNotOmnidirectional','S0-D-v1 Beam.SideDown_dB must equal 0.');
end
end
function S=fieldStructLocal(P,name)
if isfield(P,name) && isstruct(P.(name)), S=P.(name); else, S=struct(); end
end
function value=fieldLocal(S,name,defaultValue)
if isfield(S,name) && ~isempty(S.(name)), value=S.(name); else, value=defaultValue; end
end
function value=positiveScalarLocal(value,name)
value=double(value);
if ~isscalar(value)||~isreal(value)||~isfinite(value)||value<=0
    error('G3:InvalidPositiveScalar','%s must be a finite positive scalar.',name);
end
end
function value=logicalScalarLocal(value,name)
if ~(isscalar(value) && (islogical(value) || isnumeric(value)))
    error('G3:InvalidLogicalScalar','%s must be a logical scalar.',name);
end
value=logical(value);
end
