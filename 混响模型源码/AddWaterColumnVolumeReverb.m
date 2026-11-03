function [yScaAug,yVolume,info] = AddWaterColumnVolumeReverb(ySca,yDir,timeRt,InputParams)
%ADDWATERCOLUMEVOLUMEREVERB 独立水体体积混响的统计时域实现。
% 该分量与NRL近海面气泡云模型完全分开。固定种子的带限复高斯过程表示
% 大量不可分辨水体散射体的非相干和；功率包络使用双程传播常见的幂律衰减。
% 它只加入散射通道，不修改直达通道、边界冲激响应或几何到达时间。

ySca=ySca(:); yDir=yDir(:); t=timeRt(:);
N=min([numel(ySca),numel(yDir),numel(t)]);
ySca=ySca(1:N); yDir=yDir(1:N); t=t(1:N);
enabled=logical(fieldOrLocal(InputParams,'EnableWaterColumnVolume',false));
V=fieldOrLocal(InputParams,'WaterColumnVolume',struct());
if ~enabled || ~logical(fieldOrLocal(V,'Enable',false))
    yVolume=complex(zeros(N,1)); yScaAug=ySca;
    info=struct('Enabled',false,'Reason','surface reverberation is disabled');
    return;
end

fs=double(InputParams.fs);
% 使用直达复波形的绝对峰时刻；不能用滑动功率窗的左沿作为参考，否则
% 体积项门控会被人为提前约半个窗长。
[~,idxDirect]=max(abs(yDir));
tDirect=t(idxDirect);
delay=t-tDirect;
delayRef=double(V.ReferenceDelaySec);
% 近程分量补偿直达后至第一海底到达前的水体散射，采用快速指数衰减；
% 远程分量在第一海底到达附近平滑接管，并按幂律保持长时尾部。
nearRise=c2RiseLocal(delay,double(V.NearOnsetDelaySec),double(V.NearFullDelaySec));
nearFall=c2FallLocal(delay,double(V.NearFadeDelaySec),double(V.NearOffDelaySec));
nearTransferPower=10.^(double(V.NearReferenceTransferLevelDb)/10).* ...
    10.^(-double(V.NearDecayRateDbPerSec).* ...
    max(delay-double(V.NearReferenceDelaySec),0)/10).*nearRise.*nearFall;
nearTransferPower(delay<=double(V.NearOnsetDelaySec))=0;

gate=c2RiseLocal(delay,double(V.OnsetDelaySec),double(V.FullDelaySec));
positiveDelay=max(delay,delayRef/100);
farTransferPower=10.^(double(V.ReferenceTransferLevelDb)/10).* ...
    (positiveDelay/delayRef).^(-double(V.PowerLawExponent)).*gate;
farTransferPower(delay<=double(V.OnsetDelaySec))=0;
transferPower=nearTransferPower+farTransferPower;

previousRng=rng;
restoreRng=onCleanup(@() rng(previousRng)); %#ok<NASGU>
rng(double(V.RandomSeed),'twister');
z=(randn(N,1)+1i*randn(N,1))/sqrt(2);
[b,a]=butter(4,[double(V.BandLowHz) double(V.BandHighHz)]/(fs/2),'bandpass');
z=filtfilt(b,a,real(z))+1i*filtfilt(b,a,imag(z));
normMask=delay>=double(V.FullDelaySec) & delay<=min(delayRef+2,t(end)-tDirect);
if nnz(normMask)<max(10,round(0.1*fs)), normMask=delay>=double(V.FullDelaySec); end
z=z/sqrt(mean(abs(z(normMask)).^2,'omitnan'));
yVolume=sqrt(max(transferPower,0)).*z;
yScaAug=ySca+yVolume;

info=struct( ...
    'Enabled',true, ...
    'Model','band-limited incoherent water-column scatterers with power-law decay', ...
    'DistinctFromSurfaceBubbleCloud',true, ...
    'DirectTimeSec',tDirect, ...
    'NearReferenceDelaySec',double(V.NearReferenceDelaySec), ...
    'NearReferenceReceivedLevelDb',double(InputParams.SourceLevel)+double(V.NearReferenceTransferLevelDb), ...
    'NearDecayRateDbPerSec',double(V.NearDecayRateDbPerSec), ...
    'NearGateDelaySec',[double(V.NearOnsetDelaySec) double(V.NearFullDelaySec) ...
        double(V.NearFadeDelaySec) double(V.NearOffDelaySec)], ...
    'ReferenceDelaySec',delayRef, ...
    'ReferenceTransferLevelDb',double(V.ReferenceTransferLevelDb), ...
    'ReferenceReceivedLevelDb',double(InputParams.SourceLevel)+double(V.ReferenceTransferLevelDb), ...
    'PowerLawExponent',double(V.PowerLawExponent), ...
    'OnsetDelaySec',double(V.OnsetDelaySec), ...
    'FullDelaySec',double(V.FullDelaySec), ...
    'FrequencyBandHz',[double(V.BandLowHz) double(V.BandHighHz)], ...
    'RandomSeed',double(V.RandomSeed), ...
    'DirectChannelModified',false, ...
    'BoundaryImpulseResponsesModified',false, ...
    'IncludedInBTR',false);
fprintf(['Water-column volume reverberation: ON, reference RL %.2f dB at %.2f s ' ...
    'after direct, power exponent %.2f, near-field RL %.2f dB at %.2f s, ' ...
    'band %.1f-%.1f Hz.\n'], ...
    info.ReferenceReceivedLevelDb,info.ReferenceDelaySec,info.PowerLawExponent, ...
    info.NearReferenceReceivedLevelDb,info.NearReferenceDelaySec, ...
    info.FrequencyBandHz);
end

function g=c2FallLocal(x,a,b)
g=ones(size(x)); g(x>=b)=0;
idx=x>a & x<b; u=(x(idx)-a)/(b-a);
g(idx)=1-(6*u.^5-15*u.^4+10*u.^3);
end

function g=c2RiseLocal(x,a,b)
g=zeros(size(x)); g(x>=b)=1;
idx=x>a & x<b; u=(x(idx)-a)/(b-a);
g(idx)=6*u.^5-15*u.^4+10*u.^3;
end

function value=fieldOrLocal(S,name,defaultValue)
if isstruct(S)&&isfield(S,name)&&~isempty(S.(name)), value=S.(name); else, value=defaultValue; end
end
