function [M,envelope,peaks] = ComputePaperResponseMetrics20ms_v2(z,fs,windowStartS,windowEndS,label)
%ComputePaperResponseMetrics20ms_v2 Accepted Layer-B RL metric authority.
arguments
    z {mustBeNumeric}
    fs (1,1) double {mustBeFinite,mustBePositive}
    windowStartS (1,1) double {mustBeFinite} = 0
    windowEndS (1,1) double {mustBeFinite,mustBePositive} = 60
    label (1,1) string = "response"
end
t=(0:numel(z)-1)'/fs;q=t>=windowStartS&t<windowEndS;
assert(nnz(q)>1,'P20v2:EmptyMetricWindow','Metric window has insufficient samples.');
powerAll=abs(z(:)).^2;
smoothSamples=round(.05*fs);
smoothPowerAll=movmean(powerAll,smoothSamples); % accepted default endpoint='shrink'
rlAll=10*log10(max(smoothPowerAll,1e-20));
x=z(q);tq=t(q);power=powerAll(q);rl=rlAll(q);
energy=sum(power,'double')/fs;
cum=cumsum(power);total=cum(end);
if total>0,i50=find(cum>=.5*total,1);i90=find(cum>=.9*total,1);t50=tq(i50);t90=tq(i90);else,t50=NaN;t90=NaN;end
blockSamples=round(.010*fs);nBlock=floor(numel(x)/blockSamples);
xp=reshape(power(1:nBlock*blockSamples),blockSamples,nBlock);env=sqrt(mean(xp,1,'double')).';
envT=windowStartS+((0:nBlock-1)'+.5)*blockSamples/fs;
envelope=table(repmat(label,nBlock,1),envT,env,'VariableNames',{'Label','TimeS','RMSAmplitude'});
isPeak=false(nBlock,1);if nBlock>=3,isPeak(2:end-1)=env(2:end-1)>=env(1:end-2)&env(2:end-1)>env(3:end);end
idx=find(isPeak);if isempty(idx),[~,idx]=max(env);end
prom=zeros(numel(idx),1);neighE=zeros(numel(idx),1);
for k=1:numel(idx),ii=idx(k);lo=max(1,ii-2);hi=min(nBlock,ii+2);prom(k)=env(ii)-max(min(env(lo:ii)),min(env(ii:hi)));tq0=envT(ii);qq=tq>=tq0-.010&tq<tq0+.010;neighE(k)=sum(power(qq),'double')/fs;end
[~,ord]=sort(env(idx),'descend');ord=ord(1:min(10,numel(ord)));idx=idx(ord);prom=prom(ord);neighE=neighE(ord);rank=(1:numel(idx)).';
peaks=table(repmat(label,numel(idx),1),rank,envT(idx),env(idx),prom,neighE,'VariableNames',{'Label','AmplitudeRank','TimeS','RMSAmplitude','Prominence','NeighborhoodEnergy20ms'});
chron=sort(envT(idx));intervals=diff(chron);[major,im]=max(env);
M=struct('MetricVersion','P20_PRIMARY_RESPONSE_v2','RLMetricAuthorityVersion','P20_RL_METRIC_AUTHORITY_v1', ...
    'Label',label,'WindowIdentity','Wformal_[0,60s)_v1','WindowStartS',windowStartS,'WindowEndExclusiveS',windowEndS, ...
    'Population','all observed complex-response samples in Wformal', ...
    'EnergyFormula','sum(abs(z)^2)/Fs','RLDistanceStatistic','arithmetic mean / type-7 linear percentile of RL samples', ...
    'RLNormalizationReference','common shape-normalized response power; absolute source calibration absent', ...
    'RLPopulation','RL samples after full-response 50-ms moving-mean power smoothing, restricted to Wformal', ...
    'RLSmoothingDurationS',.05,'RLSmoothingSampleCount',smoothSamples,'RLSmoothingImplementation','movmean(power,round(0.05*Fs))', ...
    'RLEdgeBehavior','MATLAB movmean default endpoint shrink','RLPowerFloor',1e-20,'RLLogConvention','10*log10(power)', ...
    'RLPercentileConvention','sorted x; u=1+(N-1)*p/100; linear interpolation between floor(u),ceil(u)', ...
    'WindowEnergy',energy,'MeanRLdB',mean(rl),'P50RLdB',percentileLocal(rl,50),'P95RLdB',percentileLocal(rl,95), ...
    't50S',t50,'t90S',t90,'EnvelopeBinS',.010,'MajorPeakTimeS',envT(im),'MajorPeakRMSAmplitude',major, ...
    'TopKPeakCount',height(peaks),'MedianAdjacentTopKPeakIntervalS',median(intervals,'omitnan'), ...
    'MeanTopKPeakProminence',mean(prom,'omitnan'),'SumTopKNeighborhoodEnergy',sum(neighE,'double'), ...
    'OldInstantaneousPowerRLStatus','SUPERSEDED_DIAGNOSTIC_ONLY','AbsoluteRLAccuracyClaim','NOT_AUTHORIZED');
end
function q=percentileLocal(x,p),x=sort(x(:));u=1+(numel(x)-1)*p/100;l=floor(u);z=ceil(u);q=x(l)+(u-l)*(x(z)-x(l));end
