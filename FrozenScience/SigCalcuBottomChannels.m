function [ChannelResults, elapsedTime, traversalInfo] = SigCalcuBottomChannels(InputParams, PropagationChannels, Channels)
%SigCalcuBottomChannels Traverse one bottom grid and evaluate all channels.
[InputParams,D,G3Audit] = ResolveG3Parameters(InputParams,'channels');
[InputParams, RandomInfo] = ResolveRandomRealization(InputParams);
timer = tic;
nCh = numel(Channels);
fs = InputParams.fs;
nPoints = ceil(fieldOrLocal(InputParams,'TWindowCompute',InputParams.TWindow) * fs + 1);
recvRange = InputParams.RecvRange;
scatter=InputParams.ScatteringResolved;
disableAdditionalRandomPhase=InputParams.Model.DisableAdditionalRandomPhase;
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

[xValues,xWidthsM] = BuildBottomXValues(D.XmaxM,recvRange,D.GridI, ...
    D.GridIPlusM,D.BoundaryPolicy);
hBottomByX = cell(numel(xValues),1);
eventListsByX = cell(numel(xValues),1);
cellCountsByX = zeros(numel(xValues),1);
progressStep = max(1,floor(numel(xValues)/10));
cancelFlagFile = fieldOrLocal(InputParams,'CancelFlagFile','');
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
    gridX = xValues(xNum);
    gridRow=BuildBottomGridRow(gridX,xWidthsM(xNum),D.YmaxM,recvRange, ...
        D.GridI,D.GridIPlusM,D.TotalTwoLegHorizontalRangeLimitM,D.BoundaryPolicy);
    for gridIndex=1:numel(gridRow.Y)
        checkCancelFlagLocal(cancelFlagFile);
        if ~gridRow.Within80kmMask(gridIndex), break; end
            localCellCount = localCellCount + 1;
            gridY = gridRow.Y(gridIndex);
            cellArea=gridRow.CellArea(gridIndex);
            [dInIdx,dOutIdx,~,cosPhi] = TriAngle(0,0,gridX,gridY,recvRange,0);
            % All frequency channels use this exact same physical cell.
            % No JSON-controlled jitter or second grid traversal is used.
            x = gridX; y = gridY; jx = 0; jy = 0;
            phiS = WrapAzimuth180(atan2d(y,x));
            phiR = WrapAzimuth180(atan2d(y,x-recvRange));
            cellKey = BuildScatterCellKey('bottom', gridX, gridY);
            [~, cellKeyId] = StableKeyHash('cell', cellKey);
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
                        [ms1,ms2]=ScatterFunc(thetaIn,thetaOut,cosPhi, ...
                            scatter.ThtRad,scatter.MiuLinear,1);
                        scatterStrength=ms1+scatter.vLinear*ms2;
                        ampIn=double(arrIn(dInIdx).A(nIn));
                        ampOut=double(arrOut(dOutIdx).A(nOut));
                        counts=[arrivalLocal(arrIn(dInIdx),'NumBotBnc',nIn),arrivalLocal(arrIn(dInIdx),'NumTopBnc',nIn), ...
                            arrivalLocal(arrOut(dOutIdx),'NumBotBnc',nOut),arrivalLocal(arrOut(dOutIdx),'NumTopBnc',nOut)];
                        pathInstanceKey = BuildScatterPathInstanceKey( ...
                            nIn,nOut,counts,delayIn,delayOut);
                        [~,pathInstanceId] = StableKeyHash('path',pathInstanceKey);
                        phaseInfo=ResolveEventPhase(RandomInfo,'bottom',cellKey,pathInstanceKey, ...
                            disableAdditionalRandomPhase);
                        phaseValue=phaseInfo.RandomPhase;
                        gain=ampIn*ampOut*sqrt(max(0,scatterStrength*cellArea))*ampWeight*phaseInfo.Multiplier;
                        localHBottom(ch,sampleIndex)=localHBottom(ch,sampleIndex)+gain;
                        ev=emptyEvent;
                        ev=fillEventLocal(ev,totalDelay,gain,phiS,phiR,x,y,gridX,gridY,jx,jy,cellArea, ...
                            'bottom',srcAngle,double(arrOut(dOutIdx).SrcDeclAngle(nOut)),delayIn,delayOut, ...
                            counts,phaseValue,cellKeyId,ampWeight,powerWeight,region,ch,Channels(ch));
                        ev.Z=bottomDepth;
                        ev=fillRandomEventFieldsLocal(ev,RandomInfo,cellKey,pathInstanceKey, ...
                            pathInstanceId,phaseInfo.EventKey,phaseInfo.EventKeyId, ...
                            phaseInfo.RandomBase,phaseInfo.RandomPhase,phaseInfo.UsesRandomPhase);
                        localEvents{ch}(end+1,1)=ev; %#ok<AGROW>
                    end
                end
            end
    end
    hBottomByX{xNum}=localHBottom;
    eventListsByX{xNum}=localEvents;
    cellCountsByX(xNum)=localCellCount;
    send(progressQueue,xNum);
end

cellCount = sum(cellCountsByX);
for xNum = 1:numel(hBottomByX)
    hBottom = hBottom + hBottomByX{xNum};
    localEvents = eventListsByX{xNum};
    for ch = 1:nCh
        if isempty(localEvents{ch}), continue; end
        eventLists{ch} = [eventLists{ch}; localEvents{ch}(:)]; %#ok<AGROW>
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
            counts=[arrivalLocal(directArr(recIndex),'NumBotBnc',k),arrivalLocal(directArr(recIndex),'NumTopBnc',k),0,0];
            cellKey=BuildScatterCellKey('direct',recvRange,0);
            pathInstanceKey=BuildScatterPathInstanceKey(k,0,counts,delay,0);
            [~,cellKeyId]=StableKeyHash('cell',cellKey);
            [~,pathInstanceId]=StableKeyHash('path',pathInstanceKey);
            eventKey=sprintf('direct|%s|%s',cellKey,pathInstanceKey);
            [~,eventKeyId]=StableKeyHash('event',eventKey);
            ev=emptyEvent;
            ev=fillEventLocal(ev,delay,gain,0,0,recvRange,0,recvRange,0,0,0,NaN, ...
                'direct',srcAngle,arrivalLocal(directArr(recIndex),'RcvrDeclAngle',k),delay,0, ...
                counts,0,cellKeyId,ampWeight,powerWeight,region,ch,Channels(ch));
            ev=fillRandomEventFieldsLocal(ev,RandomInfo,cellKey,pathInstanceKey, ...
                pathInstanceId,eventKey,eventKeyId,0,0,false);
            ev.Z=fieldOrLocal(InputParams,'Rd',NaN);
            directEvents(end+1,1)=ev; %#ok<AGROW>
        end
    end
    ChannelResults(ch).Frequency=Channels(ch).ReferenceFrequency;
    ChannelResults(ch).Name=Channels(ch).Name;
    ChannelResults(ch).hBottom=BuildImpulseResponseFromEvents(eventLists{ch},fs,nPoints);
    ChannelResults(ch).hDir=BuildImpulseResponseFromEvents(directEvents,fs,nPoints);
    ChannelResults(ch).EventTableBottom=eventLists{ch};
    ChannelResults(ch).EventTableDirect=directEvents;
end
elapsedTime=toc(timer);
for ch=1:nCh, ChannelResults(ch).TimeCost.Bottom=elapsedTime; end
[gridAudit,~]=AuditProductionBottomGrid(InputParams,'channels');
traversalInfo=struct('BottomScatterGridTraversalCount',1,'BottomCellCount',cellCount, ...
    'GridXCount',numel(xValues),'SharedAcrossFrequencyChannels',true, ...
    'GridMode',D.BoundaryPolicy,'G3ParameterAudit',G3Audit,'ProductionGridAudit',gridAudit);

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

function value=arrivalLocal(S,name,idx)
value=NaN; if isfield(S,name) && numel(S.(name))>=idx, value=double(S.(name)(idx)); end
end
function ev=emptyEventLocal()
ev=struct('Delay',[],'ComplexGain',[],'PowerGain',[],'PhiS',[],'PhiR',[], ...
    'X',[],'Y',[],'Z',[],'CellArea',[],'ScatterType','','InterfaceType','','SrcAngle',[], ...
    'RecvSrcAngle',[],'ThetaIn',[],'ThetaOut',[],'DelayIn',[],'DelayOut',[], ...
    'NumBotIn',[],'NumTopIn',[],'NumBotOut',[],'NumTopOut',[],'PathClass','', ...
    'PathClassID',[],'BeamAmpWeight',[],'BeamPowerWeight',[],'BeamRegion','', ...
    'RandomSeedUsed',[],'RandomModel','','RandomModelVersion',[], ...
    'RandomPhase',[],'RandomBase',[],'UsesRandomPhase',[], ...
    'GridX',[],'GridY',[],'JitterX',[],'JitterY',[],'CellId',[], ...
    'CellKey','','PathInstanceId',[],'PathInstanceKey','','EventKey','','EventKeyId',[], ...
    'FrequencyChannelIndex',[],'ReferenceFrequencyHz',[],'SignalComponent','', ...
    'SignalStartTime',[]);
end
function ev=fillEventLocal(ev,delay,gain,phiS,phiR,x,y,gx,gy,jx,jy,area,typeName,srcAngle,recvAngle,delayIn,delayOut,counts,phaseValue,cellId,ampWeight,powerWeight,region,ch,channel)
ev.Delay=delay; ev.ComplexGain=gain; ev.PowerGain=abs(gain)^2; ev.PhiS=WrapAzimuth180(phiS); ev.PhiR=WrapAzimuth180(phiR);
ev.X=x; ev.Y=y; ev.Z=NaN; ev.CellArea=area; ev.ScatterType=typeName; ev.InterfaceType=typeName; ev.SrcAngle=srcAngle;
ev.RecvSrcAngle=recvAngle; ev.ThetaIn=srcAngle; ev.ThetaOut=recvAngle; ev.DelayIn=delayIn; ev.DelayOut=delayOut;
ev.NumBotIn=counts(1); ev.NumTopIn=counts(2); ev.NumBotOut=counts(3); ev.NumTopOut=counts(4);
ev.PathClass=sprintf('%s_B%dT%d_to_B%dT%d',typeName,counts(1),counts(2),counts(3),counts(4));
ev.PathClassID=stableHashLocal(counts); ev.BeamAmpWeight=ampWeight; ev.BeamPowerWeight=powerWeight; ev.BeamRegion=region;
ev.RandomPhase=phaseValue; ev.RandomBase=phaseValue/(2*pi);
ev.GridX=gx; ev.GridY=gy; ev.JitterX=jx; ev.JitterY=jy; ev.CellId=cellId;
ev.FrequencyChannelIndex=ch; ev.ReferenceFrequencyHz=channel.ReferenceFrequency;
ev.SignalComponent=channel.SignalType; ev.SignalStartTime=channel.SignalStartTime;
end
function ev=fillRandomEventFieldsLocal(ev,info,cellKey,pathKey,pathId,eventKey,eventId,randomBase,randomPhase,usesRandom)
ev.RandomSeedUsed=info.RandomSeedUsed; ev.RandomModel=info.RandomModel;
ev.RandomModelVersion=info.RandomModelVersion; ev.RandomBase=randomBase;
ev.RandomPhase=randomPhase; ev.UsesRandomPhase=logical(usesRandom);
ev.CellKey=cellKey; ev.PathInstanceId=pathId; ev.PathInstanceKey=pathKey;
ev.EventKey=eventKey; ev.EventKeyId=eventId;
end
function id=stableHashLocal(values)
id=uint32(5381); values=double(values(:));
for k=1:numel(values), id=uint32(mod(double(id)*33+mod(round(values(k)),65521),2^32-1)); end
id=double(id);
end
