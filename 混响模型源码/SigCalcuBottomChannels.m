function [ChannelResults, elapsedTime, traversalInfo] = SigCalcuBottomChannels(InputParams, PropagationChannels, Channels, SaveEvents)
%SigCalcuBottomChannels Traverse one bottom grid and evaluate all channels.
timer = tic;
nCh = numel(Channels);
fs = InputParams.fs;
nPoints = ceil(InputParams.TWindowCompute * fs + 1);
Rmax = InputParams.Rmax;
recvRange = InputParams.RecvRange;
bottomDepth = fieldOrLocal(InputParams,'WaterDepth',NaN);
if (~isfinite(bottomDepth) || bottomDepth <= 0) && isfield(InputParams,'SSP') && ...
        isnumeric(InputParams.SSP) && ~isempty(InputParams.SSP)
    bottomDepth = max(double(InputParams.SSP(:,1)),[],'omitnan');
end
emptyEvent = emptyEventLocal();

template = struct('Frequency',0,'Name','','hBottom',[],'hDir',[], ...
    'EventTableBottom',[],'EventTableDirect',[],'TimeCost',struct());
ChannelResults = repmat(template,nCh,1);
hBottom = complex(zeros(nCh,nPoints));
hDir = complex(zeros(nCh,nPoints));
eventLists = cell(nCh,1);
for ch=1:nCh, eventLists{ch}=repmat(emptyEvent,0,1); end

[xValues,precision] = adaptiveXLocal(Rmax,recvRange);
xCellOffsets = bottomCellOffsetsLocal(xValues,Rmax,recvRange,precision);
hBottomByX = cell(numel(xValues),1);
eventListsByX = cell(numel(xValues),1);
cellCountsByX = zeros(numel(xValues),1);
progressStep = max(1,floor(numel(xValues)/10));
cancelFlagFile = fieldOrLocal(InputParams,'CancelFlagFile','');
eventDelayWindows = normalizeEventDelayWindowsLocal( ...
    fieldOrLocal(InputParams,'EventDelayWindows',[]));
completedX = 0;
progressQueue = parallel.pool.DataQueue;
afterEach(progressQueue,@updateProgressLocal);
fprintf('Shared bottom grid: %d x positions, %d frequency channel(s).\n', ...
    numel(xValues),nCh);
fprintf('Shared bottom grid uses parallel x traversal; each x evaluates all frequency channels together.\n');
parfor xNum = 1:numel(xValues)
    checkCancelFlagLocal(cancelFlagFile);
    localHBottom = complex(zeros(nCh,nPoints));
    localEvents = cell(nCh,1);
    for localCh=1:nCh
        localEvents{localCh}=repmat(emptyEvent,0,1);
    end
    localCellCount = 0;
    cellCount = xCellOffsets(xNum);
    gridX = xValues(xNum);
    yAbs = 0;
    breadth = 1;
    yIndex = 0;
    while yAbs <= Rmax
        checkCancelFlagLocal(cancelFlagFile);
        yIndex = yIndex + 1;
        [dInIdx,dOutIdx,~,cosPhi] = TriAngle(0,0,gridX,yAbs,recvRange,0);
        if dInIdx+dOutIdx > 80000, break; end
        if xNum == 1, long = 1; else, long = round(abs((gridX-recvRange)/2)/precision.i+precision.iplus); end
        cellArea = breadth*long;
        if yAbs==0, signs=1; else, signs=[1 -1]; end
        for signValue = signs
            cellCount = cellCount + 1;
            localCellCount = localCellCount + 1;
            gridY = signValue*yAbs;
            % All frequency channels use this exact same physical cell.
            % No JSON-controlled jitter or second grid traversal is used.
            x = gridX; y = gridY; jx = 0; jy = 0;
            phiS = atan2d(y,x);
            phiR = atan2d(y,x-recvRange);
            for ch = 1:nCh
                arrIn = PropagationChannels(ch).Bottom.SourceToBottom;
                arrOut = PropagationChannels(ch).Bottom.BottomToReceiver;
                if dInIdx>numel(arrIn) || dOutIdx>numel(arrOut), continue; end
                for nIn=1:double(arrIn(dInIdx).Narr)
                    for nOut=1:double(arrOut(dOutIdx).Narr)
                        delayIn=real(double(arrIn(dInIdx).delay(nIn)));
                        delayOut=real(double(arrOut(dOutIdx).delay(nOut)));
                        totalDelay=delayIn+delayOut;
                        if delayIn<=0 || delayOut<=0 || totalDelay >= (nPoints-1)/fs-InputParams.Itg, continue; end
                        sampleIndex=round(totalDelay*fs)+1;
                        if sampleIndex<1 || sampleIndex>nPoints, continue; end
                        srcAngle=double(arrIn(dInIdx).SrcDeclAngle(nIn));
                        [keep,powerWeight,ampWeight,region] = GetBeamWeight(srcAngle,phiS,InputParams.Beam);
                        if ~keep, continue; end
                        thetaIn=abs(double(arrIn(dInIdx).RcvrDeclAngle(nIn)));
                        thetaOut=abs(double(arrOut(dOutIdx).SrcDeclAngle(nOut)));
                        [ms1,ms2]=ScatterFunc(thetaIn,thetaOut,cosPhi,InputParams.Tht, ...
                            10^(InputParams.Miu/10),1);
                        scatterStrength=ms1+10^(InputParams.v/10)*ms2;
                        ampIn=double(arrIn(dInIdx).A(nIn));
                        ampOut=double(arrOut(dOutIdx).A(nOut));
                        counts=[arrivalLocal(arrIn(dInIdx),'NumBotBnc',nIn),arrivalLocal(arrIn(dInIdx),'NumTopBnc',nIn), ...
                            arrivalLocal(arrOut(dOutIdx),'NumBotBnc',nOut),arrivalLocal(arrOut(dOutIdx),'NumTopBnc',nOut)];
                        pathKey=pathKeyLocal('bottom',counts);
                        phaseValue=2*pi*SharedScatterUnitValue(cellCount,pathKey);
                        gain=ampIn*ampOut*sqrt(max(0,scatterStrength*cellArea))*ampWeight*exp(1i*phaseValue);
                        localHBottom(ch,sampleIndex)=localHBottom(ch,sampleIndex)+gain;
                        if SaveEvents && isDelayCapturedLocal(totalDelay,eventDelayWindows)
                            ev=emptyEvent;
                            ev=fillEventLocal(ev,totalDelay,gain,phiS,phiR,x,y,gridX,gridY,jx,jy,cellArea, ...
                                'bottom',srcAngle,double(arrOut(dOutIdx).SrcDeclAngle(nOut)),delayIn,delayOut, ...
                                counts,pathKey,phaseValue,cellCount,ampWeight,powerWeight,region,ch,Channels(ch));
                            ev.Z=bottomDepth;
                            localEvents{ch}(end+1,1)=ev; %#ok<AGROW>
                        end
                    end
                end
            end
        end
        breadth=round(abs(yAbs+(gridX-recvRange)/2)/precision.i+precision.iplus);
        yAbs=round(yAbs+abs(yAbs+(gridX-recvRange)/2)/precision.i+precision.iplus);
    end
    % Exact double values with sparse zero storage; avoid retaining one
    % complete dense time matrix per grid column during parfor collection.
    hBottomByX{xNum}=sparse(localHBottom);
    eventListsByX{xNum}=localEvents;
    cellCountsByX(xNum)=localCellCount;
    send(progressQueue,xNum);
end

cellCount = sum(cellCountsByX);
for xNum = 1:numel(hBottomByX)
    hBottom = hBottom + hBottomByX{xNum};
    if SaveEvents
        localEvents = eventListsByX{xNum};
        for ch = 1:nCh
            if isempty(localEvents{ch}), continue; end
            eventLists{ch} = [eventLists{ch}; localEvents{ch}(:)]; %#ok<AGROW>
        end
    end
end

for ch=1:nCh
    directEvents=repmat(emptyEvent,0,1);
    directArr=PropagationChannels(ch).Bottom.SourceToReceiver;
    recIndex=min(2,numel(directArr));
    if recIndex>=1
        for k=1:double(directArr(recIndex).Narr)
            delay=real(double(directArr(recIndex).delay(k)));
            idx=round(delay*fs)+1;
            if idx<1 || idx>nPoints, continue; end
            srcAngle=double(directArr(recIndex).SrcDeclAngle(k));
            [keep,powerWeight,ampWeight,region]=GetBeamWeight(srcAngle,0,InputParams.Beam);
            if ~keep, continue; end
            gain=double(directArr(recIndex).A(k))*ampWeight;
            hDir(ch,idx)=hDir(ch,idx)+gain;
            if SaveEvents
                counts=[arrivalLocal(directArr(recIndex),'NumBotBnc',k),arrivalLocal(directArr(recIndex),'NumTopBnc',k),0,0];
                ev=emptyEvent;
                ev=fillEventLocal(ev,delay,gain,0,0,recvRange,0,recvRange,0,0,0,NaN, ...
                    'direct',srcAngle,arrivalLocal(directArr(recIndex),'RcvrDeclAngle',k),delay,0, ...
                    counts,pathKeyLocal('direct',counts),0,0,ampWeight,powerWeight,region,ch,Channels(ch));
                ev.Z=fieldOrLocal(InputParams,'Rd',NaN);
                directEvents(end+1,1)=ev; %#ok<AGROW>
            end
        end
    end
    ChannelResults(ch).Frequency=Channels(ch).ReferenceFrequency;
    ChannelResults(ch).Name=Channels(ch).Name;
    ChannelResults(ch).hBottom=hBottom(ch,:);
    ChannelResults(ch).hDir=hDir(ch,:);
    ChannelResults(ch).EventTableBottom=eventLists{ch};
    ChannelResults(ch).EventTableDirect=directEvents;
end
elapsedTime=toc(timer);
for ch=1:nCh, ChannelResults(ch).TimeCost.Bottom=elapsedTime; end
traversalInfo=struct('BottomScatterGridTraversalCount',1,'BottomCellCount',cellCount, ...
    'GridXCount',numel(xValues),'SharedAcrossFrequencyChannels',true, ...
    'GridMode','fixed_adaptive_coordinates');

    function updateProgressLocal(~)
        completedX = completedX + 1;
        if completedX == 1 || mod(completedX,progressStep) == 0 || ...
                completedX == numel(xValues)
            fprintf('Shared bottom grid completed x=%d/%d (%d%%).\n', ...
                completedX,numel(xValues),round(100*completedX/numel(xValues)));
        end
        drawnow limitrate;
    end
end

function checkCancelFlagLocal(flagFile)
if ~isempty(flagFile) && exist(char(string(flagFile)),'file') == 2
    error('Reverb:ModelRunStopped','用户已请求停止运行。');
end
end

function value = fieldOrLocal(S,name,defaultValue)
if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
    value = S.(name);
else
    value = defaultValue;
end
end

function windows=normalizeEventDelayWindowsLocal(value)
% EventDelayWindows is an internal diagnostic control. Empty means that
% every event is retained, preserving the production/BTR behaviour. A
% finite N-by-2 matrix retains only events in the requested delay windows,
% avoiding a multi-gigabyte event table during path-family audits.
if isempty(value)
    windows=[];
    return;
end
windows=double(value);
if size(windows,2)~=2 || any(~isfinite(windows),'all') || ...
        any(windows(:,1)<0) || any(windows(:,2)<windows(:,1))
    error('SigCalcuBottomChannels:EventDelayWindows', ...
        'EventDelayWindows must be a finite N-by-2 matrix with 0<=start<=end.');
end
windows=sortrows(windows,1);
end

function tf=isDelayCapturedLocal(delay,windows)
tf=isempty(windows) || any(delay>=windows(:,1) & delay<=windows(:,2));
end

function [xValues,p] = adaptiveXLocal(X,recvRange)
p=struct('i',30,'iplus',100); x=-X; xValues=[];
while x<=X
    xValues(end+1)=x; %#ok<AGROW>
    x=round(x+abs((x-recvRange)/2)/p.i+p.iplus);
end
end
function offsets = bottomCellOffsetsLocal(xValues,Rmax,recvRange,p)
counts=zeros(numel(xValues),1);
for ix=1:numel(xValues)
    gridX=xValues(ix); yAbs=0; n=0;
    while yAbs<=Rmax
        [dInIdx,dOutIdx]=TriAngle(0,0,gridX,yAbs,recvRange,0);
        if dInIdx+dOutIdx>80000, break; end
        if yAbs==0, n=n+1; else, n=n+2; end
        yAbs=round(yAbs+abs(yAbs+(gridX-recvRange)/2)/p.i+p.iplus);
    end
    counts(ix)=n;
end
offsets=[0; cumsum(counts(1:end-1))];
end
function value=arrivalLocal(S,name,idx)
value=NaN; if isfield(S,name) && numel(S.(name))>=idx, value=double(S.(name)(idx)); end
end
function key=pathKeyLocal(typeName,counts)
key=double(typeName); key=[key(:); double(counts(:))];
end
function ev=emptyEventLocal()
ev=struct('Delay',[],'ComplexGain',[],'PowerGain',[],'PhiS',[],'PhiR',[], ...
    'X',[],'Y',[],'Z',[],'CellArea',[],'ScatterType','','SrcAngle',[], ...
    'RecvSrcAngle',[],'ThetaIn',[],'ThetaOut',[],'DelayIn',[],'DelayOut',[], ...
    'NumBotIn',[],'NumTopIn',[],'NumBotOut',[],'NumTopOut',[],'PathClass','', ...
    'PathClassID',[],'BeamAmpWeight',[],'BeamPowerWeight',[],'BeamRegion','', ...
    'RandomPhase',[],'RandomBase',[], ...
    'GridX',[],'GridY',[],'JitterX',[],'JitterY',[],'CellId',[], ...
    'FrequencyChannelIndex',[],'ReferenceFrequencyHz',[],'SignalComponent','', ...
    'SignalStartTime',[]);
end
function ev=fillEventLocal(ev,delay,gain,phiS,phiR,x,y,gx,gy,jx,jy,area,typeName,srcAngle,recvAngle,delayIn,delayOut,counts,pathKey,phaseValue,cellId,ampWeight,powerWeight,region,ch,channel)
ev.Delay=delay; ev.ComplexGain=gain; ev.PowerGain=abs(gain)^2; ev.PhiS=phiS; ev.PhiR=phiR;
ev.X=x; ev.Y=y; ev.Z=NaN; ev.CellArea=area; ev.ScatterType=typeName; ev.SrcAngle=srcAngle;
ev.RecvSrcAngle=recvAngle; ev.ThetaIn=srcAngle; ev.ThetaOut=recvAngle; ev.DelayIn=delayIn; ev.DelayOut=delayOut;
ev.NumBotIn=counts(1); ev.NumTopIn=counts(2); ev.NumBotOut=counts(3); ev.NumTopOut=counts(4);
ev.PathClass=sprintf('%s_B%dT%d_to_B%dT%d',typeName,counts(1),counts(2),counts(3),counts(4));
ev.PathClassID=stableHashLocal(pathKey); ev.BeamAmpWeight=ampWeight; ev.BeamPowerWeight=powerWeight; ev.BeamRegion=region;
ev.RandomPhase=phaseValue; ev.RandomBase=phaseValue/(2*pi);
ev.GridX=gx; ev.GridY=gy; ev.JitterX=jx; ev.JitterY=jy; ev.CellId=cellId;
ev.FrequencyChannelIndex=ch; ev.ReferenceFrequencyHz=channel.ReferenceFrequency;
ev.SignalComponent=channel.SignalType; ev.SignalStartTime=channel.SignalStartTime;
end
function id=stableHashLocal(values)
id=uint32(5381); values=double(values(:));
for k=1:numel(values), id=uint32(mod(double(id)*33+mod(round(values(k)),65521),2^32-1)); end
id=double(id);
end
