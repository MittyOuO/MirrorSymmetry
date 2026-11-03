function [ChannelResults, elapsedTime, traversalInfo] = SigCalcuSurfaceChannels(InputParams, PropagationChannels, Channels, SaveEvents)
%SigCalcuSurfaceChannels Traverse one surface grid and evaluate all channels.
timer=tic; nCh=numel(Channels); fs=InputParams.fs;
nPoints=ceil(InputParams.TWindowCompute*fs+1); Rmax=InputParams.Rmax; recvRange=InputParams.RecvRange;
emptyEvent=emptyEventLocal();
template=struct('hSurface',[],'EventTableSurface',[],'TimeCost',struct());
ChannelResults=repmat(template,nCh,1); hSurface=complex(zeros(nCh,nPoints)); eventLists=cell(nCh,1);
for ch=1:nCh, eventLists{ch}=repmat(emptyEvent,0,1); end
[xValues,p]=adaptiveXLocal(Rmax,recvRange);
xCellOffsets=surfaceCellOffsetsLocal(xValues,Rmax,recvRange,p);
hSurfaceByX=cell(numel(xValues),1);
eventListsByX=cell(numel(xValues),1);
cellCountsByX=zeros(numel(xValues),1);
progressStep=max(1,floor(numel(xValues)/10));
cancelFlagFile=fieldOrLocal(InputParams,'CancelFlagFile','');
completedX=0;
progressQueue=parallel.pool.DataQueue;
afterEach(progressQueue,@updateProgressLocal);
fprintf('Shared surface grid: %d x positions, %d frequency channel(s).\n',numel(xValues),nCh);
fprintf('Shared surface grid uses parallel x traversal; each x evaluates all frequency channels together.\n');
% NRL总海面散射：粗糙界面功率与近表层气泡云体积散射功率相加。
% 本函数只在OptionBorder==0（勾选海面混响）时调用，因此无需新增开关。
As=19/1e5; gamma2=3.8; ssopt=0;
parfor xNum=1:numel(xValues)
    checkCancelFlagLocal(cancelFlagFile);
    localHSurface=complex(zeros(nCh,nPoints));
    localEvents=cell(nCh,1);
    for localCh=1:nCh
        localEvents{localCh}=repmat(emptyEvent,0,1);
    end
    localCellCount=0;
    cellCount=xCellOffsets(xNum);
    gridX=xValues(xNum); yAbs=0; breadth=1;
    while yAbs<=Rmax
        checkCancelFlagLocal(cancelFlagFile);
        [dInIdx,dOutIdx,~,cosPhi]=TriAngle(0,0,gridX,yAbs,recvRange,0);
        if dInIdx+dOutIdx>80000, break; end
        if xNum==1, long=1; else, long=round(abs((gridX-recvRange)/2)/p.i+p.iplus); end
        area=breadth*long; if yAbs==0, signs=1; else, signs=[1 -1]; end
        for signValue=signs
            cellCount=cellCount+1; localCellCount=localCellCount+1; gridY=signValue*yAbs;
            % Every frequency is evaluated at the same unjittered cell.
            x=gridX; y=gridY; jx=0; jy=0;
            phiS=atan2d(y,x); phiR=atan2d(y,x-recvRange); phiOut=acosd(max(-1,min(1,cosPhi)));
            for ch=1:nCh
                arrIn=PropagationChannels(ch).Surface.SourceToSurface;
                arrOut=PropagationChannels(ch).Surface.SurfaceToReceiver;
                if dInIdx>numel(arrIn) || dOutIdx>numel(arrOut), continue; end
                for nIn=1:double(arrIn(dInIdx).Narr)
                    for nOut=1:double(arrOut(dOutIdx).Narr)
                        delayIn=real(double(arrIn(dInIdx).delay(nIn))); delayOut=real(double(arrOut(dOutIdx).delay(nOut)));
                        totalDelay=delayIn+delayOut;
                        thetaIn=double(arrIn(dInIdx).RcvrDeclAngle(nIn)); thetaOut=double(arrOut(dOutIdx).RcvrDeclAngle(nOut));
                        if arrivalLocal(arrIn(dInIdx),'NumBotBnc',nIn)>1 || arrivalLocal(arrOut(dOutIdx),'NumBotBnc',nOut)>0 || ...
                                delayIn<=0 || delayOut<=0 || totalDelay>=(nPoints-1)/fs-InputParams.Itg || thetaIn>=0 || thetaOut>=0
                            continue;
                        end
                        idx=round(totalDelay*fs)+1; if idx<1 || idx>nPoints, continue; end
                        srcAngle=double(arrIn(dInIdx).SrcDeclAngle(nIn));
                        [keep,powerWeight,ampWeight,region]=GetBeamWeight(srcAngle,phiS,InputParams.Beam); if ~keep, continue; end
                        ssdB=sssnrl(Channels(ch).ReferenceFrequency,PropagationChannels(ch).SurfaceSoundSpeed, ...
                            InputParams.U,As,gamma2,abs(thetaIn),abs(thetaOut),phiOut,ssopt);
                        strength=10^(ssdB/10);
                        counts=[arrivalLocal(arrIn(dInIdx),'NumBotBnc',nIn),arrivalLocal(arrIn(dInIdx),'NumTopBnc',nIn), ...
                            arrivalLocal(arrOut(dOutIdx),'NumBotBnc',nOut),arrivalLocal(arrOut(dOutIdx),'NumTopBnc',nOut)];
                        pathKey=pathKeyLocal('surface',counts); phaseValue=2*pi*SharedScatterUnitValue(cellCount,pathKey);
                        gain=double(arrIn(dInIdx).A(nIn))*double(arrOut(dOutIdx).A(nOut))*sqrt(max(0,strength*area))*ampWeight*exp(1i*phaseValue);
                        localHSurface(ch,idx)=localHSurface(ch,idx)+gain;
                        if SaveEvents
                            ev=emptyEvent; ev=fillEventLocal(ev,totalDelay,gain,phiS,phiR,x,y,gridX,gridY,jx,jy,area, ...
                                srcAngle,double(arrOut(dOutIdx).SrcDeclAngle(nOut)),thetaIn,thetaOut,delayIn,delayOut, ...
                                counts,pathKey,phaseValue,cellCount,ampWeight,powerWeight,region,ch,Channels(ch));
                            localEvents{ch}(end+1,1)=ev; %#ok<AGROW>
                        end
                    end
                end
            end
        end
        breadth=round(abs(yAbs+(gridX-recvRange)/2)/p.i+p.iplus);
        yAbs=round(yAbs+abs(yAbs+(gridX-recvRange)/2)/p.i+p.iplus);
    end
    hSurfaceByX{xNum}=localHSurface;
    eventListsByX{xNum}=localEvents;
    cellCountsByX(xNum)=localCellCount;
    send(progressQueue,xNum);
end

cellCount=sum(cellCountsByX);
for xNum=1:numel(hSurfaceByX)
    hSurface=hSurface+hSurfaceByX{xNum};
    if SaveEvents
        localEvents=eventListsByX{xNum};
        for ch=1:nCh
            if isempty(localEvents{ch}), continue; end
            eventLists{ch}=[eventLists{ch}; localEvents{ch}(:)]; %#ok<AGROW>
        end
    end
end
elapsedTime=toc(timer);
for ch=1:nCh
    ChannelResults(ch).hSurface=hSurface(ch,:);
    ChannelResults(ch).EventTableSurface=eventLists{ch};
    ChannelResults(ch).TimeCost.Surface=elapsedTime;
end
traversalInfo=struct('SurfaceScatterGridTraversalCount',1,'SurfaceCellCount',cellCount, ...
    'GridXCount',numel(xValues),'SharedAcrossFrequencyChannels',true, ...
    'GridMode','fixed_adaptive_coordinates');

    function updateProgressLocal(~)
        completedX=completedX+1;
        if completedX==1 || mod(completedX,progressStep)==0 || ...
                completedX==numel(xValues)
            fprintf('Shared surface grid completed x=%d/%d (%d%%).\n', ...
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

function value=fieldOrLocal(S,name,defaultValue)
if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
    value=S.(name);
else
    value=defaultValue;
end
end

function [xValues,p]=adaptiveXLocal(X,recvRange)
p=struct('i',30,'iplus',100); x=-X; xValues=[];
while x<=X, xValues(end+1)=x; x=round(x+abs((x-recvRange)/2)/p.i+p.iplus); end %#ok<AGROW>
end
function offsets=surfaceCellOffsetsLocal(xValues,Rmax,recvRange,p)
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
function key=pathKeyLocal(typeName,counts), key=[double(typeName(:));double(counts(:))]; end
function ev=emptyEventLocal()
ev=struct('Delay',[],'ComplexGain',[],'PowerGain',[],'PhiS',[],'PhiR',[], ...
    'X',[],'Y',[],'Z',0,'CellArea',[],'ScatterType','surface','SrcAngle',[], ...
    'RecvSrcAngle',[],'ThetaIn',[],'ThetaOut',[],'DelayIn',[],'DelayOut',[], ...
    'NumBotIn',[],'NumTopIn',[],'NumBotOut',[],'NumTopOut',[],'PathClass','', ...
    'PathClassID',[],'BeamAmpWeight',[],'BeamPowerWeight',[],'BeamRegion','', ...
    'RandomPhase',[],'RandomBase',[], ...
    'GridX',[],'GridY',[],'JitterX',[],'JitterY',[],'CellId',[], ...
    'FrequencyChannelIndex',[],'ReferenceFrequencyHz',[],'SignalComponent','', ...
    'SignalStartTime',[]);
end
function ev=fillEventLocal(ev,delay,gain,phiS,phiR,x,y,gx,gy,jx,jy,area,srcAngle,recvAngle,thetaIn,thetaOut,delayIn,delayOut,counts,pathKey,phaseValue,cellId,ampWeight,powerWeight,region,ch,channel)
ev.Delay=delay; ev.ComplexGain=gain; ev.PowerGain=abs(gain)^2; ev.PhiS=phiS; ev.PhiR=phiR;
ev.X=x; ev.Y=y; ev.CellArea=area; ev.SrcAngle=srcAngle; ev.RecvSrcAngle=recvAngle; ev.ThetaIn=thetaIn; ev.ThetaOut=thetaOut;
ev.DelayIn=delayIn; ev.DelayOut=delayOut; ev.NumBotIn=counts(1); ev.NumTopIn=counts(2); ev.NumBotOut=counts(3); ev.NumTopOut=counts(4);
ev.PathClass=sprintf('surface_B%dT%d_to_B%dT%d',counts(1),counts(2),counts(3),counts(4)); ev.PathClassID=stableHashLocal(pathKey);
ev.BeamAmpWeight=ampWeight; ev.BeamPowerWeight=powerWeight; ev.BeamRegion=region; ev.RandomPhase=phaseValue;
ev.RandomBase=phaseValue/(2*pi); ev.GridX=gx; ev.GridY=gy; ev.JitterX=jx; ev.JitterY=jy; ev.CellId=cellId;
ev.FrequencyChannelIndex=ch; ev.ReferenceFrequencyHz=channel.ReferenceFrequency; ev.SignalComponent=channel.SignalType; ev.SignalStartTime=channel.SignalStartTime;
end
function id=stableHashLocal(values)
id=uint32(5381); values=double(values(:));
for k=1:numel(values), id=uint32(mod(double(id)*33+mod(round(values(k)),65521),2^32-1)); end
id=double(id);
end
