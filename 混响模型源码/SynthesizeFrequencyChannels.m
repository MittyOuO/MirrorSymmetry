function [ChannelResults,yDir,ySca,yTotal,timeRt,TxWave,yBottom,ySurface] = SynthesizeFrequencyChannels(InputParams,Channels,ChannelResults)
%SynthesizeFrequencyChannels Convolve components and add them in complex linear time.
% A shared CW/HFM propagation channel deliberately carries the complete
% composite TxSigInput.  Therefore the same h(t) is convolved with the CW
% tone and with the original full-band HFM waveform; sharing a propagation
% frequency never replaces the HFM waveform with a CW waveform.
fs=InputParams.fs;
nOut=ceil(InputParams.TWindowDisplay*fs)+1;
yDir=complex(zeros(nOut,1)); ySca=complex(zeros(nOut,1));
yBottom=complex(zeros(nOut,1)); ySurface=complex(zeros(nOut,1));
for ch=1:numel(Channels)
    P=InputParams; P.TxSigInput=Channels(ch).TxSigInput;
    [yd,ys,t,tx]=ApplyTimeSmearing(ChannelResults(ch).hSca, ...
        ChannelResults(ch).hDir,InputParams.SpreadTime,P);
    yd=yd(:); ys=ys(:);
    startSample=round(Channels(ch).SignalStartTime*fs)+1;
    yDir=placeAndAddLocal(yDir,yd,startSample,nOut);
    ySca=placeAndAddLocal(ySca,ys,startSample,nOut);
    % 散射通道不使用直达波展宽核，因此同一发射波形可精确分解海底/海面项。
    yb=conv(ChannelResults(ch).hBottom(:),tx.st(:),'full');
    yu=conv(ChannelResults(ch).hSurface(:),tx.st(:),'full');
    yBottom=placeAndAddLocal(yBottom,yb,startSample,nOut);
    ySurface=placeAndAddLocal(ySurface,yu,startSample,nOut);
    ChannelResults(ch).yDirComponent=yd(1:min(end,nOut));
    ChannelResults(ch).yScaComponent=ys(1:min(end,nOut));
    ChannelResults(ch).timeComponent=t(1:min(end,nOut));
    ChannelResults(ch).TxWave=tx;
    ChannelResults(ch).StartSample=startSample;
end
componentError=max(abs(ySca-(yBottom+ySurface)),[],'omitnan');
componentScale=max(1,max(abs(ySca),[],'omitnan'));
assert(componentError<=1e-10*componentScale, ...
    '海底/海面时域分量之和与总边界散射不一致。');
yTotal=yDir+ySca;
timeRt=(0:nOut-1).'/fs;
[fullWave,fullTime,meta,components]=GenerateTxSignal(InputParams.TxSigInput);
TxWave=struct('st',fullWave,'t',fullTime,'fs',fs,'SigMeta',meta,'SigComponents',components);
end

function target=placeAndAddLocal(target,source,startSample,nOut)
if startSample>nOut || isempty(source), return; end
n=min(numel(source),nOut-startSample+1);
target(startSample:startSample+n-1)=target(startSample:startSample+n-1)+source(1:n);
end
