function [ChannelResults, info] = ImpulseResponseChannels(InputParams, OptionBorder, TempWorkDir, SaveEvents)
%ImpulseResponseChannels Multi-frequency propagation with one grid traversal.
Channels=ResolveFrequencyChannels(InputParams);
propTimer=tic;
[PropagationChannels,Jobs,BellhopDispatch]=PreparePropagationChannels( ...
    InputParams,Channels,OptionBorder,TempWorkDir);
propTime=toc(propTimer);
parallelInfo=ensureScatterParallelPoolLocal(InputParams);
try
    [ChannelResults,bottomTime,bottomTraversal]=SigCalcuBottomChannels( ...
        InputParams,PropagationChannels,Channels,SaveEvents);
catch ME
    rethrowAsStopIfRequestedLocal(ME,InputParams);
end

surfaceTraversal=struct('SurfaceScatterGridTraversalCount',0,'SurfaceCellCount',0);
surfaceTime=0;
if OptionBorder==0
    try
        [surfaceResults,surfaceTime,surfaceTraversal]=SigCalcuSurfaceChannels( ...
            InputParams,PropagationChannels,Channels,SaveEvents);
    catch ME
        rethrowAsStopIfRequestedLocal(ME,InputParams);
    end
else
    surfaceResults=repmat(struct('hSurface',[],'EventTableSurface',[],'TimeCost',struct()),numel(Channels),1);
end

for ch=1:numel(Channels)
    if OptionBorder==0
        hSurface=surfaceResults(ch).hSurface;
        if InputParams.EnableSurfaceDynamic
            [hSurface,spreadInfo]=ApplySurfaceDynamicSpread(hSurface,InputParams.fs,InputParams.U,InputParams);
        else
            spreadInfo=struct('Enabled',false,'Reason','disabled');
        end
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
    'Profile','','RequestedWorkers',0,'ActualWorkers',0, ...
    'StartedNow',false,'ReusedExistingPool',false,'Message','');
useParallel=true;
if isfield(InputParams,'UseScatterParallel') && ~isempty(InputParams.UseScatterParallel)
    useParallel=logical(InputParams.UseScatterParallel);
end
info.Requested=useParallel;
if ~useParallel
    info.Message='UseScatterParallel=false';
    return;
end

% One local process pool is created once and then reused by every theta
% case in this EXE.  Request the complete capacity advertised by the local
% Processes profile; never impose the donor's historical two-worker cap.
cluster=parcluster('Processes');
requestedWorkers=max(1,floor(double(cluster.NumWorkers)));
info.Profile=char(cluster.Profile);
info.RequestedWorkers=requestedWorkers;
pool=gcp('nocreate');
if isempty(pool)
    pool=parpool(cluster,requestedWorkers);
    info.StartedNow=true;
else
    info.ReusedExistingPool=true;
end
info.Active=~isempty(pool);
if ~info.Active
    error('ImpulseResponseChannels:ParallelPoolUnavailable', ...
        'The local parallel pool was not created.');
end
info.NumWorkers=pool.NumWorkers;
info.ActualWorkers=pool.NumWorkers;
if pool.NumWorkers~=requestedWorkers
    error('ImpulseResponseChannels:InsufficientParallelWorkers', ...
        ['Processes profile advertises %d workers, but the active pool has %d. ' ...
         'Refusing to continue with a silently reduced pool.'], ...
        requestedWorkers,pool.NumWorkers);
end
if info.StartedNow
    action='started once for this EXE process';
else
    action='reused from the preceding theta case';
end
info.Message=sprintf('scatter parfor pool active with %d workers; %s', ...
    pool.NumWorkers,action);
fprintf('[Parallel] profile=%s, requested=%d, actual=%d, reused=%d\n', ...
    info.Profile,requestedWorkers,pool.NumWorkers,info.ReusedExistingPool);
fprintf('Shared scatter grid parallel pool: %d worker(s), %s.\n', ...
    pool.NumWorkers,action);
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
