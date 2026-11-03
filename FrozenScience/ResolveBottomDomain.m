function [D, Audit] = ResolveBottomDomain(InputParams, consumerProfile)
%ResolveBottomDomain Resolve grid, rectangular domain and propagation ranges.

if nargin < 2 || isempty(consumerProfile), consumerProfile='single'; end
consumerProfile = lower(strtrim(char(string(consumerProfile))));
convention = scatteringConventionLocal(InputParams);

if strcmp(convention,'canonical')
    rmax = requiredPositiveLocal(InputParams,'RmaxM');
    G = requiredStructLocal(InputParams,'ScatterGrid');
    gridI = requiredPositiveLocal(G,'GridI');
    gridIPlusM = requiredPositiveLocal(G,'GridIPlusM');
    P = requiredStructLocal(requiredStructLocal(InputParams,'Propagation'),'Bottom');
    angleStep = requiredPositiveLocal(P,'LaunchAngleStepDeg');
    rangeStep = requiredPositiveLocal(P,'RangeStepM');
    if abs(rangeStep-1)>32*eps
        error('G3:FormalRangeStepLockedAt1m', ...
            'Paper-eligible S0-D requires BellhopRangeStepM = 1 m; received %.17g m.',rangeStep);
    end
    boundaryPolicy = 'strict_rectangular_voronoi';
    paperEligible = true;
else
    if isfield(InputParams,'RmaxM') && ~isempty(InputParams.RmaxM)
        rmax = positiveScalarLocal(InputParams.RmaxM,'RmaxM');
    elseif isfield(InputParams,'Rmax') && ~isempty(InputParams.Rmax)
        rmax = positiveScalarLocal(InputParams.Rmax,'Rmax');
    elseif strcmp(consumerProfile,'single_direct')
        rmax = 50000;
    else
        rmax = 60000;
    end
    if strcmp(consumerProfile,'fast_rl') && rmax < 1000
        rmax = rmax*1000;
    end
    if isfield(InputParams,'ScatterGrid') && isstruct(InputParams.ScatterGrid)
        gridI = fieldPositiveLocal(InputParams.ScatterGrid,'GridI',30);
        gridIPlusM = fieldPositiveLocal(InputParams.ScatterGrid,'GridIPlusM',100);
    else
        gridI=30; gridIPlusM=100;
    end
    angleStep=0.01; rangeStep=1;
    if isfield(InputParams,'Propagation') && isstruct(InputParams.Propagation) && ...
            isfield(InputParams.Propagation,'Bottom') && isstruct(InputParams.Propagation.Bottom)
        angleStep=fieldPositiveLocal(InputParams.Propagation.Bottom,'LaunchAngleStepDeg',angleStep);
        rangeStep=fieldPositiveLocal(InputParams.Propagation.Bottom,'RangeStepM',rangeStep);
    end
    if strcmp(consumerProfile,'channels')
        boundaryPolicy='legacy_channels_pre_increment';
    else
        boundaryPolicy='legacy_single_post_increment';
    end
    paperEligible=false;
end

recvRange = requiredPositiveLocal(InputParams,'RecvRange');
D = struct();
D.InputConvention=convention;
D.PaperEligible=paperEligible;
D.RmaxM=rmax; D.XmaxM=rmax; D.YmaxM=rmax;
D.GridI=gridI; D.GridIPlusM=gridIPlusM;
D.BoundaryPolicy=boundaryPolicy;
D.BellhopLaunchAngleStepDeg=angleStep;
D.BellhopRangeStepM=rangeStep;
D.SourceToBottomRangeMaxM=hypot(D.XmaxM,D.YmaxM);
D.BottomToReceiverRangeMaxM=hypot(D.XmaxM+recvRange,D.YmaxM);
D.SourceToReceiverRangeMaxM=recvRange;
D.TotalTwoLegHorizontalRangeLimitM=80000;
D.SourceToBottomSpec=BuildBellhopRangeSpec( ...
    D.SourceToBottomRangeMaxM,rangeStep,'source_to_bottom');
D.BottomToReceiverSpec=BuildBellhopRangeSpec( ...
    D.BottomToReceiverRangeMaxM,rangeStep,'bottom_to_receiver');
D.SourceToReceiverSpec=BuildBellhopRangeSpec( ...
    D.SourceToReceiverRangeMaxM,rangeStep,'source_to_receiver');
if strcmp(convention,'canonical')
    propagationProfile='formal';
elseif strcmp(consumerProfile,'channels')
    propagationProfile='legacy_channels';
elseif strcmp(consumerProfile,'fast_rl')
    propagationProfile='legacy_fast_rl';
else
    propagationProfile='legacy_single';
end
D.PropagationSpec=PrepareBottomPropagationSpec(D,recvRange,propagationProfile);
Audit=D;
Audit.RmaxSemantics='half_width_of_rectangular_bottom_candidate_domain';
Audit.SourceToBottomRangeFormula='hypot(XmaxM,YmaxM)';
Audit.BottomToReceiverRangeFormula='hypot(XmaxM+RecvRangeM,YmaxM)';
Audit.SourceToReceiverRangeFormula='RecvRangeM';
Audit.BellhopRangeStepRole='fixed_1m_paper_numerical_definition_not_convergence_variable';
end

function convention=scatteringConventionLocal(P)
convention='legacy';
if isfield(P,'Scattering') && isstruct(P.Scattering) && ...
        isfield(P.Scattering,'Bottom') && isstruct(P.Scattering.Bottom) && ...
        isfield(P.Scattering.Bottom,'InputConvention') && ...
        ~isempty(P.Scattering.Bottom.InputConvention)
    convention=lower(strtrim(char(string(P.Scattering.Bottom.InputConvention))));
end
if ~ismember(convention,{'legacy','canonical'})
    error('G3:UnknownScatteringConvention','Unknown InputConvention: %s.',convention);
end
end
function S=requiredStructLocal(P,name)
if ~isfield(P,name) || ~isstruct(P.(name)), error('G3:MissingStruct','Missing struct %s.',name); end
S=P.(name);
end
function value=requiredPositiveLocal(S,name)
if ~isfield(S,name) || isempty(S.(name)), error('G3:MissingParameter','Missing %s.',name); end
value=positiveScalarLocal(S.(name),name);
end
function value=fieldPositiveLocal(S,name,defaultValue)
if isfield(S,name) && ~isempty(S.(name)), value=positiveScalarLocal(S.(name),name); else, value=defaultValue; end
end
function value=positiveScalarLocal(value,name)
value=double(value);
if ~isscalar(value) || ~isreal(value) || ~isfinite(value) || value<=0
    error('G3:InvalidPositiveScalar','%s must be a finite positive scalar.',name);
end
end
