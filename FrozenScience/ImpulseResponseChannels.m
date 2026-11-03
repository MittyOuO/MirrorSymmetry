function [ChannelResults, info] = ImpulseResponseChannels(InputParams, OptionBorder, TempWorkDir)
%ImpulseResponseChannels Multi-frequency propagation with one grid traversal.
[InputParams,~,g3Audit] = ResolveG3Parameters(InputParams,'channels');
[InputParams, randomInfo] = ResolveRandomRealization(InputParams);
Channels=ResolveFrequencyChannels(InputParams);
propTimer=tic;
[PropagationChannels,Jobs,BellhopDispatch]=PreparePropagationChannels( ...
    InputParams,Channels,OptionBorder,TempWorkDir);
propTime=toc(propTimer);
parallelInfo=ensureScatterParallelPoolLocal(InputParams);
try
    [ChannelResults,bottomTime,bottomTraversal]=SigCalcuBottomChannels( ...
        InputParams,PropagationChannels,Channels);
catch ME
    rethrowAsStopIfRequestedLocal(ME,InputParams);
end

surfaceTraversal=struct('SurfaceScatterGridTraversalCount',0,'SurfaceCellCount',0);
surfaceTime=0;
if OptionBorder==0
    try
        [surfaceResults,surfaceTime,surfaceTraversal]=SigCalcuSurfaceChannels( ...
            InputParams,PropagationChannels,Channels);
    catch ME
        rethrowAsStopIfRequestedLocal(ME,InputParams);
    end
else
    surfaceResults=repmat(struct('hSurface',[],'EventTableSurface',[],'TimeCost',struct()),numel(Channels),1);
end

for ch=1:numel(Channels)
    if OptionBorder==0
        hSurface=surfaceResults(ch).hSurface;
        spreadInfo=struct('Enabled',false,'Reason', ...
            'deferred: event-table/impulse-response closure keeps raw event response');
    else
        hSurface=zeros(size(ChannelResults(ch).hBottom));
        spreadInfo=struct('Enabled',false,'Reason','bottom_only');
    end
    ChannelResults(ch).hSurface=hSurface;
    ChannelResults(ch).hSca=ChannelResults(ch).hBottom+hSurface;
    ChannelResults(ch).EventTableSurface=surfaceResults(ch).EventTableSurface;
    ChannelResults(ch).EventTable=concatEventsLocal(ChannelResults(ch).EventTableBottom, ...
        ChannelResults(ch).EventTableSurface,ChannelResults(ch).EventTableDirect);
    ChannelResults(ch).SurfaceSpreadInfo=spreadInfo;
    ChannelResults(ch).SignalType=Channels(ch).SignalType;
    ChannelResults(ch).SignalStartTime=Channels(ch).SignalStartTime;
    ChannelResults(ch).SignalDuration=Channels(ch).SignalDuration;
    ChannelResults(ch).TimeCost.Propagation=propTime;
    ChannelResults(ch).TimeCost.Bottom=bottomTime;
    ChannelResults(ch).TimeCost.Surface=surfaceTime;
end

expected=numel(Channels)*(3+2*(OptionBorder==0));
info=struct('FrequencyChannels',Channels,'PropagationChannels',PropagationChannels, ...
    'BellhopJobs',Jobs,'BellhopJobCountExpected',expected, ...
    'BellhopJobCountActual',sum([Jobs.success]),'BellhopDispatch',BellhopDispatch, ...
    'ScatterParallel',parallelInfo, ...
    'RandomRealization',randomInfo, ...
    'G3ParameterAudit',g3Audit, ...
    'BottomTraversal',bottomTraversal, ...
    'SurfaceTraversal',surfaceTraversal,'TimeCost',struct('Propagation',propTime, ...
    'Bottom',bottomTime,'Surface',surfaceTime,'Total',propTime+bottomTime+surfaceTime));
end

function rethrowAsStopIfRequestedLocal(ME,InputParams)
flagFile='';
if isstruct(InputParams) && isfield(InputParams,'CancelFlagFile')
    flagFile=InputParams.CancelFlagFile;
end
if strcmp(ME.identifier,'Reverb:ModelRunStopped') || ...
        (~isempty(flagFile) && exist(char(string(flagFile)),'file')==2)
    error('Reverb:ModelRunStopped','用户已请求停止运行。');
end
rethrow(ME);
end

function info=ensureScatterParallelPoolLocal(InputParams)
info=struct('Requested',true,'Active',false,'NumWorkers',0, ...
    'StartedNow',false,'ReusedExistingPool',false,'Message','');
try
    useParallel=true;
    if isfield(InputParams,'UseScatterParallel') && ~isempty(InputParams.UseScatterParallel)
        useParallel=logical(InputParams.UseScatterParallel);
    end
    info.Requested=useParallel;
    if ~useParallel
        info.Message='UseScatterParallel=false';
        return;
    end
    pool=gcp('nocreate');
    if isempty(pool)
        pool=parpool;
        info.StartedNow=true;
    else
        info.ReusedExistingPool=true;
    end
    info.Active=~isempty(pool);
    if info.Active
        info.NumWorkers=pool.NumWorkers;
        if info.StartedNow
            action='started once for this EXE process';
        else
            action='reused from the preceding theta case';
        end
        info.Message=sprintf('scatter parfor pool active with %d workers; %s', ...
            pool.NumWorkers,action);
        fprintf('Shared scatter grid parallel pool: %d worker(s), %s.\n', ...
            pool.NumWorkers,action);
    end
catch ME
    info.Message=ME.message;
    warning('ImpulseResponseChannels:ParallelPoolUnavailable', ...
        'Unable to start scatter parfor pool; MATLAB will continue with available execution mode: %s',ME.message);
end
end

function E=concatEventsLocal(varargin)
E=[];
for k=1:nargin
    value=varargin{k};
    if isempty(value), continue; end
    if isempty(E), E=value(:); else
        [E,value]=alignFieldsLocal(E(:),value(:)); E=[E;value]; %#ok<AGROW>
    end
end
end
function [A,B]=alignFieldsLocal(A,B)
allFields=union(fieldnames(A),fieldnames(B),'stable');
for k=1:numel(allFields)
    f=allFields{k};
    if ~isfield(A,f), [A.(f)]=deal([]); end
    if ~isfield(B,f), [B.(f)]=deal([]); end
end
A=orderfields(A,allFields); B=orderfields(B,allFields);
end
