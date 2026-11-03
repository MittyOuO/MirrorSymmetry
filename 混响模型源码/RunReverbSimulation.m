function Results = RunReverbSimulation(InputParams, OptionBorder, RunMode, StatusFcn)
%RunReverbSimulation Single-case core entry with shared multi-frequency grids.
if nargin<2 || isempty(OptionBorder), OptionBorder=fieldOrLocal(InputParams,'OptionBorder',1); end
if nargin<3 || isempty(RunMode), RunMode=fieldOrLocal(InputParams,'RunMode',2); end
if nargin<4, StatusFcn=[]; end
notifyLocal(StatusFcn,'--- Starting single-case reverberation simulation ---');
wallTimer=tic;

originalDir=pwd;
tempDir=fieldOrLocal(InputParams,'TempWorkDir','');
if isempty(tempDir), tempDir=[tempname '_ZSDXReverb']; end
if exist(tempDir,'dir') && ~fieldOrLocal(InputParams,'KeepTempFiles',false)
    try, rmdir(tempDir,'s'); catch, end
end
if ~exist(tempDir,'dir'), mkdir(tempDir); end
InputParams.TempWorkDir=tempDir; InputParams.OriginalDir=originalDir;
cleanup=onCleanup(@() cleanupLocal(originalDir,tempDir,fieldOrLocal(InputParams,'KeepTempFiles',false))); %#ok<NASGU>

Channels=ResolveFrequencyChannels(InputParams);
Results=struct('RunMode',RunMode,'OptionBorder',OptionBorder,'InputParams',InputParams, ...
    'FrequencyChannels',Channels,'fs',InputParams.fs,'fsCalc',InputParams.fs,'TimeCost',struct());

skipFast=logical(fieldOrLocal(InputParams,'SkipFastRL',false));
requireFast=logical(fieldOrLocal(InputParams,'RequireFastRL',false));
if RunMode==2 && ~skipFast
    fastTimer=tic;
    fastInput=InputParams; fastInput.f0=Channels(1).ReferenceFrequency;
    try
        [Results.RLFast,Results.timeFast,Results.FastInfo]=FastRLCompute(fastInput,OptionBorder, ...
            'RecvRange',InputParams.RecvRange,'TempWorkDir',tempDir,'KeepTempFiles',true,'Rmax',InputParams.Rmax);
        Results.TimeCost.FastRL=toc(fastTimer);
    catch ME
        Results.FastRLError=ME.message;
        Results.FastRLErrorIdentifier=ME.identifier;
        Results.FastRLErrorReport=getReport(ME,'extended','hyperlinks','off');
        Results.FastInfo=[]; Results.TimeCost.FastRL=toc(fastTimer);
        if requireFast
            strictME=MException('RunReverbSimulation:FastRLFailed', ...
                '指定阵元快速 RL 失败 [%s]：%s',ME.identifier,ME.message);
            strictME=addCause(strictME,ME);
            throwAsCaller(strictME);
        end
        warning('RunReverbSimulation:FastRLFailed','FastRL failed; phase-preserving path continues: %s',ME.message);
    end
else
    Results.TimeCost.FastRL=NaN; Results.TimeCost.FastRLTotal=NaN;
    Results.TimeCost.ParallelSetup=0; Results.FastInfo=[];
    notifyLocal(StatusFcn,'SkipFastRL=true: FastRLCompute was not called.');
end

saveEvents=logical(fieldOrLocal(InputParams,'SaveEvents',fieldOrLocal(InputParams,'NeedBTR',false)));
phaseTimer=tic;
notifyLocal(StatusFcn,sprintf( ...
    'Starting one shared scatter-grid traversal for %d frequency channel(s).', ...
    numel(Channels)));
[ChannelResults,phaseInfo]=ImpulseResponse(InputParams,OptionBorder,tempDir,saveEvents,'multi_channel');
Results.TimeCost.PhaseEvent=toc(phaseTimer);
Results.PropagationInfo=phaseInfo;
if fieldOrLocal(InputParams,'NeedBTR',false)
    for ch=1:numel(ChannelResults)
        ChannelResults(ch).EventTable=CompactBTREventTable(ChannelResults(ch).EventTable);
        ChannelResults(ch).EventTableBottom=[];
        ChannelResults(ch).EventTableSurface=[];
        ChannelResults(ch).EventTableDirect=[];
    end
end
notifyLocal(StatusFcn,sprintf( ...
    'Shared scatter-grid event calculation complete in %.3f s.', ...
    Results.TimeCost.PhaseEvent));

synthesisTimer=tic;
notifyLocal(StatusFcn,'Starting complex linear time-domain channel synthesis.');
[ChannelResults,Results.yDir,Results.ySca,Results.yTotal,Results.timeRt,Results.TxWave, ...
    yBottomBoundary,ySurfaceBoundary]= ...
    SynthesizeFrequencyChannels(InputParams,Channels,ChannelResults);
[Results.ySca,Results.yVolume,Results.WaterColumnVolumeInfo]= ...
    AddWaterColumnVolumeReverb(Results.ySca,Results.yDir,Results.timeRt,InputParams);
Results.yTotal=Results.yDir+Results.ySca;
latePeakInfo=latePeakDiagnosticLocal(yBottomBoundary,ySurfaceBoundary,Results.yVolume, ...
    Results.yDir,Results.timeRt,InputParams.fs);
Results.TimeCost.Synthesis=toc(synthesisTimer);

btrTimer=tic;
if fieldOrLocal(InputParams,'NeedBTR',false)
    notifyLocal(StatusFcn,'Starting BTR synthesis from the shared event tables.');
end
[Results.BTRVisible,Results.BTRLinear,Results.timeBTR,Results.scanAngles, ...
    Results.BTRInfo,Results.BTRChannelInfo,Results.BTRDisplay,Results.BTRDisplayInfo]= ...
    SynthesizeBTRChannels(InputParams,Channels,ChannelResults);
Results.TimeCost.BTR=toc(btrTimer);
Results.BTR=Results.BTRVisible;

% Event tables exist only as an internal BTR intermediate.  Count them for
% the run summary, then release them immediately after BTR synthesis.
eventCount=0;
for ch=1:numel(ChannelResults)
    if istable(ChannelResults(ch).EventTable)
        eventCount=eventCount+height(ChannelResults(ch).EventTable);
    else
        eventCount=eventCount+numel(ChannelResults(ch).EventTable);
    end
    ChannelResults(ch).EventTableBottom=[];
    ChannelResults(ch).EventTableSurface=[];
    ChannelResults(ch).EventTableDirect=[];
    ChannelResults(ch).EventTable=[];
end
Results.BTRLinear=[];
Results.ChannelResults=ChannelResults;
Results.hDir=sumRowsLocal(ChannelResults,'hDir');
Results.hSca=sumRowsLocal(ChannelResults,'hSca');
Results.EventTableBottom=[];
Results.EventTableSurface=[];
Results.EventTableDirect=[];
Results.EventTable=[];
Results.TimeCost.Total=Results.TimeCost.PhaseEvent+Results.TimeCost.Synthesis+Results.TimeCost.BTR;
Results.TimeCost.RunWallClock=toc(wallTimer);
Results.ResultDiagnostics=struct('FrequencyChannelCount',numel(Channels), ...
    'BottomScatterGridTraversalCount',phaseInfo.BottomTraversal.BottomScatterGridTraversalCount, ...
    'SurfaceScatterGridTraversalCount',phaseInfo.SurfaceTraversal.SurfaceScatterGridTraversalCount, ...
    'SurfaceBubbleVolumeEnabled',logical(fieldOrLocal(InputParams,'EnableSurfaceBubbleVolume',false)), ...
    'WaterColumnVolumeEnabled',logical(fieldOrLocal(InputParams,'EnableWaterColumnVolume',false)), ...
    'WaterColumnVolumeIncludedInBTR',false, ...
    'LatePeakDiagnostics',latePeakInfo, ...
    'SurfaceScatteringMode',surfaceModeLocal(InputParams,OptionBorder), ...
    'SeaState',fieldOrLocal(InputParams,'SeaState',0), ...
    'WindSpeedMps',fieldOrLocal(InputParams,'U',0), ...
    'SharedGridAcrossFrequencyChannels',true, ...
    'BellhopExecutionMode',phaseInfo.BellhopDispatch.ExecutionMode, ...
    'BellhopWorkerCount',phaseInfo.BellhopDispatch.WorkerCount, ...
    'ScatterParallelActive',fieldOrLocal(phaseInfo.ScatterParallel,'Active',false), ...
    'ScatterParallelWorkerCount',fieldOrLocal(phaseInfo.ScatterParallel,'NumWorkers',0), ...
    'EventCount',eventCount, ...
    'EventTablesReleased',true, ...
    'ReceiverPitchDegUser',fieldOrLocal(InputParams,'RxArrayPitchDeg_User',0), ...
    'ReceiverPitchDegInternal',fieldOrLocal(Results.BTRInfo,'InternalPitchDeg',NaN), ...
    'BTRPhaseMode',fieldOrLocal(Results.BTRInfo,'PhaseMode',''), ...
    'BTRApplyElementDelay',fieldOrLocal(Results.BTRInfo,'ApplyElementDelay',false), ...
    'BTRSteeringMode',fieldOrLocal(Results.BTRInfo,'SteeringMode',''), ...
    'yTotalSize',size(Results.yTotal),'timeAxisEnd',Results.timeRt(end), ...
    'BTRSize',size(Results.BTRVisible));
notifyLocal(StatusFcn,sprintf('Bottom scatter-grid traversal count = %d',Results.ResultDiagnostics.BottomScatterGridTraversalCount));
notifyLocal(StatusFcn,sprintf('Surface scatter-grid traversal count = %d',Results.ResultDiagnostics.SurfaceScatterGridTraversalCount));
notifyLocal(StatusFcn,sprintf('Frequency channel count = %d',numel(Channels)));
end

function info=latePeakDiagnosticLocal(yBottom,ySurface,yVolume,yDir,t,fs)
% 对应验证图约35 s的晚到峰，仅保存来源比例等标量诊断，不增加绘图曲线。
t=t(:); yBottom=yBottom(:); ySurface=ySurface(:); yVolume=yVolume(:); yDir=yDir(:);
[~,iDirect]=max(abs(yDir)); tDirect=t(iDirect);
delay=t-tDirect; mask=delay>=20 & delay<=28;
w=max(3,round(0.05*fs));
pBottom=movmean(abs(yBottom).^2,w);
pSurface=movmean(abs(ySurface).^2,w);
pVolume=movmean(abs(yVolume).^2,w);
pTotal=movmean(abs(yBottom+ySurface+yVolume).^2,w);
idx=find(mask);
if isempty(idx)
    info=struct('Available',false,'Reason','20-28 s post-direct window is outside output');
    return;
end
[~,k]=max(pTotal(idx)); iPeak=idx(k);
p=[pBottom(iPeak) pSurface(iPeak) pVolume(iPeak)];
names={'bottom boundary','surface boundary','water-column volume'};
[~,dominantIndex]=max(p);
info=struct('Available',true,'SearchDelaySec',[20 28], ...
    'PeakDelayAfterDirectSec',delay(iPeak),'PeakSimulationTimeSec',t(iPeak), ...
    'DominantComponent',names{dominantIndex}, ...
    'BottomPowerFraction',p(1)/max(sum(p),realmin), ...
    'SurfacePowerFraction',p(2)/max(sum(p),realmin), ...
    'WaterColumnPowerFraction',p(3)/max(sum(p),realmin), ...
    'RmaxDoesNotCreatePeak',true, ...
    'Reason','legacy tuning grid used 60 km while this configuration uses 50 km');
end

function mode=surfaceModeLocal(InputParams,OptionBorder)
if OptionBorder~=0
    mode='bottom_only';
elseif fieldOrLocal(InputParams,'EnableSurfaceBubbleVolume',false)
    mode='nrl_interface_plus_bubble_cloud_power_sum';
else
    mode='interface_only';
end
end

function value=fieldOrLocal(S,name,defaultValue)
if isstruct(S)&&isfield(S,name)&&~isempty(S.(name)), value=S.(name); else, value=defaultValue; end
end
function notifyLocal(fcn,message)
disp(message); if ~isempty(fcn)&&isa(fcn,'function_handle'), try, fcn(message); catch, end, end
end
function cleanupLocal(originalDir,tempDir,keep)
try, cd(originalDir); catch, end
if ~keep && exist(tempDir,'dir'), try, rmdir(tempDir,'s'); catch, end, end
end
function h=sumRowsLocal(C,name)
h=[];
for k=1:numel(C)
    if isempty(h), h=complex(zeros(size(C(k).(name)))); end
    h=h+C(k).(name);
end
end
function E=concatChannelEventsLocal(C,name)
E=[];
for k=1:numel(C)
    value=C(k).(name); if isempty(value), continue; end
    if isempty(E), E=value(:); else, [E,value]=alignLocal(E(:),value(:)); E=[E;value]; end %#ok<AGROW>
end
end
function [A,B]=alignLocal(A,B)
f=union(fieldnames(A),fieldnames(B),'stable');
for k=1:numel(f), if ~isfield(A,f{k}),[A.(f{k})]=deal([]);end; if ~isfield(B,f{k}),[B.(f{k})]=deal([]);end; end
A=orderfields(A,f); B=orderfields(B,f);
end
