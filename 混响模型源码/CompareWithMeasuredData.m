function [vMeasFiltered, RLMeas, vSimTotal, RLSim, timeAxis, FilterInfo] = ...
    CompareWithMeasuredData(sigData, yDir, ySca, varargin)
%COMPAREWITHMEASUREDDATA Compare measured and simulated reverberation data.
%
% Recommended call (supports CW, HFM, HFM+CW and CW+HFM):
%   [vMeasFiltered,RLMeas,vSimTotal,RLSim,timeAxis] = ...
%       CompareWithMeasuredData(sigData,yDir,ySca,SignalSpec, ...
%       fsSim,fsMeas,fsComp,SourceLevel,Sensitivity,AmpGain,NL)
%
% SignalSpec may be InputParams, TxSigInput, or the Signal object decoded
% from ParanConfigToZS.json. Recognized fields include:
%   sigMod / sigType / type
%   fCW / frequency
%   fStart / startFrequency
%   fEnd / endFrequency
%   FilterGuardHz (optional, default 10 Hz)
%   NyquistGuardHz (optional)
%
% For a combined HFM/CW signal, the measured-data bandpass covers the
% complete frequency envelope:
%   [min(fCW,fStart,fEnd), max(fCW,fStart,fEnd)]
% plus FilterGuardHz on both outer edges. This prevents a CW component
% outside the HFM band from being removed.
%
% fsComp is used only by the comparison workflow. The measured waveform is
% resampled from fsMeas to fsComp, and the simulated waveform is resampled
% from fsSim to fsComp. It does not need to be stored in the JSON file.

[SignalSpec, fsSim, fsMeas, fsComp, SourceLevel, Sensitivity, AmpGain, NL] = ...
    parseInputsLocal(varargin{:});

validateattributes(sigData, {'numeric'}, {'vector','nonempty','finite'}, mfilename, 'sigData');
validateattributes(yDir, {'numeric'}, {'vector','nonempty'}, mfilename, 'yDir');
validateattributes(ySca, {'numeric'}, {'vector','nonempty'}, mfilename, 'ySca');
validateattributes(fsSim, {'numeric'}, {'scalar','real','finite','positive'}, mfilename, 'fsSim');
validateattributes(fsMeas, {'numeric'}, {'scalar','real','finite','positive'}, mfilename, 'fsMeas');
validateattributes(fsComp, {'numeric'}, {'scalar','real','finite','positive'}, mfilename, 'fsComp');

% 1. Resample and band-limit the measured voltage.
vMeasRaw = double(sigData(:).');
[pResample, qResample] = rat(double(fsComp) / double(fsMeas), 1e-12);
vMeasResampled = resample(vMeasRaw, pResample, qResample);

[fLow, fHigh, FilterInfo] = resolveFilterBandLocal(SignalSpec, fsComp);
[bFilt, aFilt] = butter(4, [fLow, fHigh] / (fsComp / 2), 'bandpass');
vMeasFiltered = filter(bFilt, aFilt, vMeasResampled);

skipPoints = min(numel(vMeasFiltered), round(0.1 * fsComp));
if skipPoints > 0
    vMeasFiltered(1:skipPoints) = 0;
end

fprintf('[CompareWithMeasuredData] measured bandpass = %.3f to %.3f Hz (%s, guard %.3f Hz).\n', ...
    fLow, fHigh, FilterInfo.Method, FilterInfo.FilterGuardHz);

% 2. Map the direct and scattered responses separately to receiver voltage.
yDir = yDir(:).';
ySca = ySca(:).';
nSim = min(numel(yDir), numel(ySca));
yDir = yDir(1:nSim);
ySca = ySca(1:nSim);
if abs(double(fsComp) - double(fsSim)) > eps(max(double(fsComp), double(fsSim)))
    [pSim, qSim] = rat(double(fsComp) / double(fsSim), 1e-12);
    yDir = resample(yDir, pSim, qSim);
    ySca = resample(ySca, pSim, qSim);
end
systemGain = 10^((SourceLevel + Sensitivity + AmpGain) / 20);
vDirSim = yDir * systemGain;
vSignalSim = (yDir + ySca) * systemGain;

% 3. 先形成“最终但尚未平移”的仿真时域与正式RL，再从正式RL的B1峰顶确定lag。
%    对齐基准与绘图/指标输入完全相同：加噪、直达限幅、0.05 s能量窗。
directDurationSec=directDurationLocal(SignalSpec);
[idxMeasMax,idxMeasDirectStart,idxMeasDirectEnd,directInfoMeas]= ...
    detectDirectEventLocal(vMeasFiltered,fsComp,directDurationSec);
[idxSimMax,idxSimDirectStart,idxSimDirectEnd,directInfoSim]= ...
    detectDirectEventLocal(vDirSim,fsComp,directDurationSec);

measuredDirectMask=false(size(vMeasFiltered));
measuredDirectMask(idxMeasDirectStart:idxMeasDirectEnd)=true;
directClipThreshold=max(abs(vMeasFiltered(measuredDirectMask)));
if ~(isfinite(directClipThreshold)&&directClipThreshold>0)
    error('CompareWithMeasuredData:InvalidDirectClipThreshold', ...
        '实测直达波窗口内没有有效的非零限幅阈值。');
end

vNoiseRms=10^(NL/20)*10^((Sensitivity+AmpGain)/20);
vNoiseUnaligned=vNoiseRms*randn(size(vSignalSim));
vSimUnalignedPreClip=real(vSignalSim+vNoiseUnaligned);
simDirectMaskOriginal=false(size(vSimUnalignedPreClip));
simDirectMaskOriginal(idxSimDirectStart:idxSimDirectEnd)=true;
overLimitUnaligned=simDirectMaskOriginal& ...
    abs(vSimUnalignedPreClip)>directClipThreshold;
vSimUnalignedTotal=vSimUnalignedPreClip;
vSimUnalignedTotal(overLimitUnaligned)= ...
    sign(vSimUnalignedPreClip(overLimitUnaligned))*directClipThreshold;

% 这两条就是后续绘图和指标使用的正式RL；不得再另建代理RL。
windowSize=max(1,round(0.05*fsComp));
energyMeas=movmean(abs(vMeasFiltered).^2,windowSize);
RLMeas=10*log10(max(energyMeas,1e-20))-(Sensitivity+AmpGain);
guardEnd=min(numel(RLMeas)-1,skipPoints+ceil(windowSize/2));
if guardEnd>=1
    RLMeas(1:guardEnd)=RLMeas(guardEnd+1);
end
energySimUnaligned=movmean(vSimUnalignedTotal.^2,windowSize);
RLSimUnaligned=10*log10(max(energySimUnaligned,1e-20))- ...
    (Sensitivity+AmpGain);

tMeasForAlignment=(0:numel(RLMeas)-1)/fsComp;
tSimForAlignment=(0:numel(RLSimUnaligned)-1)/fsComp;
alignmentSmoothWindowSec=0.05;
[idxMeasB1,b1MeasInfo]=DetectFirstBottomPeak( ...
    RLMeas,tMeasForAlignment, ...
    'SmoothWindowSec',alignmentSmoothWindowSec);
[idxSimB1,b1SimInfo]=DetectFirstBottomPeak( ...
    RLSimUnaligned,tSimForAlignment, ...
    'SmoothWindowSec',alignmentSmoothWindowSec);
% DetectFirstBottomPeak只负责自动圈定“第二个事件/B1”所在区域。最终时间锚点
% 与“指标提升”已验收方案一致：直接在正式RL上取B1局部窗内的实际峰顶，
% 不再对正式RL二次平滑。二次平滑会在宽峰/双峰形状不同时选中错误肩部，曾造成
% 检测残差为0、但图上实际峰顶仍错开约0.34 s。
b1PeakPreSec=0.60;
b1PeakPostSec=1.20;
[idxMeasB1Formal,b1MeasPeakInfo]=locateFormalRLB1PeakLocal( ...
    RLMeas,idxMeasB1,fsComp,b1PeakPreSec,b1PeakPostSec);
[idxSimB1Formal,b1SimPeakInfo]=locateFormalRLB1PeakLocal( ...
    RLSimUnaligned,idxSimB1,fsComp,b1PeakPreSec,b1PeakPostSec);
lagPoints=idxMeasB1Formal-idxSimB1Formal;

% 同一个RL确定的整数采样lag，同时施加到时域、正式RL和限幅前审计波形。
nOutput=numel(vMeasFiltered);
fillNoise=vNoiseRms*randn(1,nOutput);
vSimPreClip=shiftWithFillLocal( ...
    vSimUnalignedPreClip,lagPoints,nOutput,fillNoise);
vSimTotal=shiftWithFillLocal( ...
    vSimUnalignedTotal,lagPoints,nOutput,fillNoise);
RLSim=shiftWithFillLocal(RLSimUnaligned,lagPoints,nOutput,NL);
timeAxis=(0:nOutput-1)/fsComp;

simDirectStartAligned=idxSimDirectStart+lagPoints;
simDirectEndAligned=idxSimDirectEnd+lagPoints;
assert(simDirectEndAligned>=1&&simDirectStartAligned<=nOutput, ...
    'CompareWithMeasuredData:AlignedDirectOutsideWindow', ...
    '按正式RL的B1对齐后，仿真直达事件完全移出对比时窗。');
simClipStart=max(1,simDirectStartAligned);
simClipEnd=min(nOutput,simDirectEndAligned);
simulatedDirectMask=false(size(vSimTotal));
simulatedDirectMask(simClipStart:simClipEnd)=true;
overLimit=simulatedDirectMask&abs(vSimPreClip)>directClipThreshold;
outsideDelta=abs(vSimTotal(~simulatedDirectMask)- ...
    vSimPreClip(~simulatedDirectMask));
if isempty(outsideDelta)
    outsideChange=0;
else
    outsideChange=max(outsideDelta,[],'omitnan');
end
assert(outsideChange==0,'直达波限幅意外修改了窗口外的仿真信号。');

% 复核正式RL的实际B1峰顶；与“指标提升”方案相同，必须精确到一个采样点内。
[idxSimB1FormalAfter,b1SimPeakAlignedInfo]=locateFormalRLB1PeakLocal( ...
    RLSim,idxMeasB1Formal,fsComp,b1PeakPreSec,b1PeakPostSec);
alignmentResidualSamples=idxSimB1FormalAfter-idxMeasB1Formal;
assert(abs(alignmentResidualSamples)<=1, ...
    'CompareWithMeasuredData:RLAlignmentResidual', ...
    '正式RL的B1实际峰顶对齐残差为%d个采样点，预期不超过1。', ...
    alignmentResidualSamples);
% 旧二次平滑检测器仅保留为审计数据，不再决定最终时间轴。
[idxSimB1After,b1SimAlignedInfo]=DetectFirstBottomPeak( ...
    RLSim,timeAxis,'SmoothWindowSec',alignmentSmoothWindowSec);
smoothedDetectorResidualSamples=idxSimB1After-idxMeasB1;
FilterInfo.fsSim = fsSim;
FilterInfo.fsMeas = fsMeas;
FilterInfo.fsComp = fsComp;
FilterInfo.DirectLimiter = struct( ...
    'Enabled',true, ...
    'MeasuredDetectionMethod',directInfoMeas.Method, ...
    'SimulatedDetectionMethod',directInfoSim.Method, ...
    'MeasuredWindowSec',[timeAxis(idxMeasDirectStart) timeAxis(idxMeasDirectEnd)], ...
    'SimulatedWindowAfterB1AlignmentSec',[timeAxis(simClipStart) timeAxis(simClipEnd)], ...
    'MeasuredPeakTimeSec',timeAxis(idxMeasMax), ...
    'SimulatedPeakTimeBeforeAlignmentSec',(idxSimMax-1)/fsComp, ...
    'SimulatedPeakTimeAfterAlignmentSec',(idxSimMax+lagPoints-1)/fsComp, ...
    'AlignmentLagSec',lagPoints/fsComp, ...
    'MeasuredThresholdV',directClipThreshold, ...
    'SimulatedPreClipMaxAbsV',max(abs(vSimPreClip(simulatedDirectMask))), ...
    'SimulatedPostClipMaxAbsV',max(abs(vSimTotal(simulatedDirectMask))), ...
    'ClippedSampleCount',sum(overLimit), ...
    'OutsideWindowMaxAbsChangeV',outsideChange);
FilterInfo.PeakAlignment = struct( ...
    'Method','formal_rl_first_bottom_peak_top_common_sample_shift', ...
    'Reference','actual peak top of second event / first bottom reflection on formal RL', ...
    'AlignmentCurve','final unaligned RL after noise and direct clipping', ...
    'RLWindowSec',windowSize/fsComp, ...
    'DetectionSmoothWindowSec',alignmentSmoothWindowSec, ...
    'FormalPeakSearchWindowRelativeSec',[-b1PeakPreSec b1PeakPostSec], ...
    'AppliedTo',{{'simulated time-domain voltage','simulated RL'}}, ...
    'MeasuredPeakIndex',idxMeasB1Formal, ...
    'MeasuredPeakTimeSec',timeAxis(idxMeasB1Formal), ...
    'SimulatedPeakIndexBeforeAlignment',idxSimB1Formal, ...
    'SimulatedPeakTimeBeforeAlignmentSec',(idxSimB1Formal-1)/fsComp, ...
    'SimulatedPeakIndexAfterAlignment',idxSimB1FormalAfter, ...
    'SimulatedPeakTimeAfterAlignmentSec',timeAxis(idxSimB1FormalAfter), ...
    'LagPoints',lagPoints, ...
    'LagSec',lagPoints/fsComp, ...
    'ResidualAfterAlignmentSamples',alignmentResidualSamples, ...
    'CoarseMeasuredPeakIndex',idxMeasB1, ...
    'CoarseMeasuredPeakTimeSec',timeAxis(idxMeasB1), ...
    'CoarseSimulatedPeakIndexBeforeAlignment',idxSimB1, ...
    'CoarseSimulatedPeakTimeBeforeAlignmentSec',(idxSimB1-1)/fsComp, ...
    'SmoothedDetectorResidualAfterAlignmentSamples',smoothedDetectorResidualSamples, ...
    'MeasuredDetection',b1MeasInfo, ...
    'SimulatedDetectionBeforeAlignment',b1SimInfo, ...
    'SimulatedDetectionAfterAlignment',b1SimAlignedInfo, ...
    'MeasuredFormalPeak',b1MeasPeakInfo, ...
    'SimulatedFormalPeakBeforeAlignment',b1SimPeakInfo, ...
    'SimulatedFormalPeakAfterAlignment',b1SimPeakAlignedInfo);
FilterInfo.InitialRLGuardRepair = struct( ...
    'Enabled',guardEnd>=1, ...
    'RepairedSampleCount',max(guardEnd,0), ...
    'GuardEndTimeSec',max(guardEnd-1,0)/fsComp, ...
    'ReplacementRLdB',RLMeas(max(1,guardEnd+1)));
function [peakIndex,info]=locateFormalRLB1PeakLocal(RL,coarseIndex,fs,preSec,postSec)
% 在B1粗定位附近直接读取“正式RL”的实际峰顶，不再进行第二次平滑。
RL=real(double(RL(:).'));
n=numel(RL);
searchStart=max(1,coarseIndex-round(preSec*fs));
searchEnd=min(n,coarseIndex+round(postSec*fs));
assert(searchEnd>searchStart, ...
    'CompareWithMeasuredData:EmptyFormalRLB1Window','正式RL的B1峰顶搜索窗为空。');
segment=RL(searchStart:searchEnd);
segment(~isfinite(segment))=-Inf;
[peakValue,localIndex]=max(segment);
assert(isfinite(peakValue), ...
    'CompareWithMeasuredData:FormalRLB1PeakNotFound','正式RL的B1窗内没有有限峰值。');
peakIndex=searchStart+localIndex-1;
info=struct('Method','maximum of formal RL inside coarse B1 window', ...
    'CoarseIndex',coarseIndex,'SearchStartIndex',searchStart, ...
    'SearchEndIndex',searchEnd,'PeakIndex',peakIndex,'PeakValueDB',peakValue, ...
    'PreSec',preSec,'PostSec',postSec);
end

end

function shifted=shiftWithFillLocal(x,lagPoints,nOutput,fillValue)
% 将RL确定的同一个整数采样lag应用到任意一维时序。
x=x(:).';
if isscalar(fillValue)
    shifted=repmat(fillValue,1,nOutput);
else
    fillValue=fillValue(:).';
    assert(numel(fillValue)==nOutput, ...
        'CompareWithMeasuredData:InvalidShiftFill', ...
        '非标量移位填充值长度必须等于输出长度。');
    shifted=fillValue;
end
if lagPoints>=0
    validLength=min(numel(x),nOutput-lagPoints);
    if validLength>0
        shifted(lagPoints+(1:validLength))=x(1:validLength);
    end
else
    sourceStart=1-lagPoints;
    validLength=min(numel(x)-sourceStart+1,nOutput);
    if validLength>0
        shifted(1:validLength)=x(sourceStart:sourceStart+validLength-1);
    end
end
end

function durationSec = directDurationLocal(S)
containers = collectSignalContainersLocal(S);
durations = [];
names = {'TpCW','cwPulseWidth','TpHFM','hfmPulseWidth','duration','Duration'};
for i = 1:numel(containers)
    C = containers{i};
    for j = 1:numel(names)
        if isfield(C,names{j}) && isnumeric(C.(names{j})) && ...
                isscalar(C.(names{j})) && isfinite(C.(names{j})) && C.(names{j})>0
            durations(end+1) = double(C.(names{j})); %#ok<AGROW>
        end
    end
end
if isempty(durations), durationSec=0.5; else, durationSec=max(durations); end
durationSec=max(0.05,durationSec);
end

function [peakIndex,startIndex,endIndex,info] = detectDirectEventLocal(v,fs,durationSec)
v=double(v(:).'); n=numel(v);
w=max(3,round(0.02*fs)); energy=movmean(abs(v).^2,w);
maxEnergy=max(energy);
assert(isfinite(maxEnergy)&&maxEnergy>0, ...
    'CompareWithMeasuredData:DirectEventNotFound','无法从信号中检测直达事件。');
baselineCount=max(1,min(n,round(0.1*fs)));
baselineSamples=sort(energy(1:baselineCount));
lowCount=max(1,round(0.2*baselineCount));
baseline=median(baselineSamples(1:lowCount),'omitnan');
% 0.04 s脉冲的仿真直达可能在0.1 s基线窗内出现，门限不得因基线窗被
% 直达污染而高于事件本身；上限取峰值功率的50%，保证仍能找到最早事件。
threshold=max([maxEnergy*0.01,baseline*100,realmin]);
threshold=min(threshold,maxEnergy*0.5);
firstIndex=find(energy>=threshold,1,'first');
assert(~isempty(firstIndex), ...
    'CompareWithMeasuredData:DirectEventNotFound','未检测到超过门限的直达事件。');
searchEnd=min(n,firstIndex+round((durationSec+0.25)*fs));
[~,localPeak]=max(energy(firstIndex:searchEnd));
peakIndex=firstIndex+localPeak-1;
startIndex=max(1,firstIndex-round(0.05*fs));
endIndex=min(n,firstIndex+round((durationSec+0.25)*fs));
info=struct('Method','earliest significant energy event', ...
    'EnergyThreshold',threshold,'FirstCrossingIndex',firstIndex, ...
    'PulseDurationSec',durationSec);
end

function [SignalSpec, fsSim, fsMeas, fsComp, SourceLevel, Sensitivity, AmpGain, NL] = ...
        parseInputsLocal(varargin)
if numel(varargin) == 8 && isstruct(varargin{1})
    SignalSpec = varargin{1};
    fsSim = varargin{2};
    fsMeas = varargin{3};
    fsComp = varargin{4};
    SourceLevel = varargin{5};
    Sensitivity = varargin{6};
    AmpGain = varargin{7};
    NL = varargin{8};
else
    error('CompareWithMeasuredData:InvalidCall', [ ...
        'Recommended call: CompareWithMeasuredData(sigData,yDir,ySca,' ...
        'SignalSpec,fsSim,fsMeas,fsComp,SourceLevel,Sensitivity,AmpGain,NL).']);
end

calibration = [SourceLevel, Sensitivity, AmpGain, NL];
if any(~isfinite(double(calibration)))
    error('CompareWithMeasuredData:InvalidCalibration', ...
        'SourceLevel、Sensitivity、AmpGain 与 NL 必须为有限标量。');
end
end

function [fLow, fHigh, info] = resolveFilterBandLocal(S, fs)
containers = collectSignalContainersLocal(S);
sigMod = firstNumericLocal(containers, {'sigMod'}, []);
sigType = firstTextLocal(containers, {'sigType','SignalType','type'}, '');
fCW = firstNumericLocal(containers, {'fCW','cwFrequency','frequency'}, []);
fStart = firstNumericLocal(containers, {'fStart','startFrequency','fLow','FLow'}, []);
fEnd = firstNumericLocal(containers, {'fEnd','endFrequency','fHigh','FHigh'}, []);
f0 = firstNumericLocal(containers, {'f0','F0','fCenter','centerFrequency'}, []);
explicitBand = firstNumericLocal(containers, {'Band','FilterBand'}, []);

mode = resolveSignalModeLocal(sigMod, sigType, fCW, fStart, fEnd);
if any(strcmp(mode, {'cw','combined_hfm_cw'})) && isempty(fCW)
    fCW = f0;
end
switch mode
    case 'combined_hfm_cw'
        requireFinitePositiveLocal([fCW fStart fEnd], '组合信号的 fCW/fStart/fEnd');
        rawBand = [min([fCW fStart fEnd]), max([fCW fStart fEnd])];
        method = 'CW/HFM union envelope';
    case 'hfm'
        requireFinitePositiveLocal([fStart fEnd], 'HFM 的 fStart/fEnd');
        rawBand = sort([fStart fEnd]);
        method = 'HFM band';
    case 'cw'
        requireFinitePositiveLocal(fCW, 'CW 的 fCW');
        rawBand = [fCW fCW];
        method = 'CW protected band';
    otherwise
        if isnumeric(explicitBand) && numel(explicitBand) == 2
            rawBand = sort(double(explicitBand(:).'));
            method = 'explicit Band';
        elseif ~isempty(fStart) && ~isempty(fEnd)
            requireFinitePositiveLocal([fStart fEnd], '自定义信号的 fStart/fEnd');
            rawBand = sort([fStart fEnd]);
            method = 'custom frequency envelope';
        else
            error('CompareWithMeasuredData:MissingSignalBand', ...
                '无法从 SignalSpec 确定实测信号滤波频带。');
        end
end

guardHz = firstNumericLocal(containers, ...
    {'FilterGuardHz','BandGuardHz','FrequencyGuardHz'}, []);
if isempty(guardHz)
    guardHz = 10;
end
validateattributes(guardHz, {'numeric'}, {'scalar','real','finite','nonnegative'});

nyquist = double(fs) / 2;
nyquistGuard = firstNumericLocal(containers, {'NyquistGuardHz'}, []);
if isempty(nyquistGuard)
    nyquistGuard = min(100, max(1, 0.05 * nyquist));
end
validateattributes(nyquistGuard, {'numeric'}, {'scalar','real','finite','nonnegative'});

if rawBand(2) >= nyquist - nyquistGuard
    error('CompareWithMeasuredData:SamplingRateTooLow', ...
        ['信号频率包络上限 %.3f Hz 已达到采样率安全上限 %.3f Hz。' ...
         '请提高 fs；程序不会截掉 CW 或 HFM 频段后继续计算。'], ...
        rawBand(2), nyquist - nyquistGuard);
end

fLow = max(10, rawBand(1) - guardHz);
fHigh = min(nyquist - nyquistGuard, rawBand(2) + guardHz);
if ~(isfinite(fLow) && isfinite(fHigh) && fLow > 0 && fHigh > fLow && fHigh < nyquist)
    error('CompareWithMeasuredData:InvalidFilterBand', ...
        ['滤波频带无效：原始包络 [%.3f %.3f] Hz，保护后 [%.3f %.3f] Hz，' ...
         'Nyquist=%.3f Hz。请提高 fs 或调整保护带。'], ...
        rawBand(1), rawBand(2), fLow, fHigh, nyquist);
end

info = struct('Method', method, 'SignalMode', mode, ...
    'RawBand', rawBand, 'FilterBand', [fLow fHigh], ...
    'FilterGuardHz', guardHz, 'NyquistGuardHz', nyquistGuard, ...
    'fCW', fCW, 'fStart', fStart, 'fEnd', fEnd);
end

function mode = resolveSignalModeLocal(sigMod, sigType, fCW, fStart, fEnd)
if ~isempty(sigMod) && isscalar(sigMod) && isfinite(sigMod)
    switch round(sigMod)
        case 1
            mode = 'cw'; return;
        case 2
            mode = 'hfm'; return;
        case {3,4}
            mode = 'combined_hfm_cw'; return;
    end
end

typeKey = regexprep(upper(char(string(sigType))), '[^A-Z0-9]+', '_');
if contains(typeKey, 'HFM') && contains(typeKey, 'CW')
    mode = 'combined_hfm_cw';
elseif contains(typeKey, 'HFM')
    mode = 'hfm';
elseif contains(typeKey, 'CW')
    mode = 'cw';
elseif ~isempty(fCW) && ~isempty(fStart) && ~isempty(fEnd)
    mode = 'combined_hfm_cw';
elseif ~isempty(fStart) && ~isempty(fEnd)
    mode = 'hfm';
elseif ~isempty(fCW)
    mode = 'cw';
else
    mode = 'custom';
end
end

function containers = collectSignalContainersLocal(S)
if ~isstruct(S) || ~isscalar(S)
    error('CompareWithMeasuredData:InvalidSignalSpec', ...
        'SignalSpec 必须为标量结构体。');
end
containers = {};
if isfield(S, 'TxSigInput') && isstruct(S.TxSigInput) && isscalar(S.TxSigInput)
    containers{end+1} = S.TxSigInput; %#ok<AGROW>
end
if isfield(S, 'Signal') && isstruct(S.Signal) && isscalar(S.Signal)
    containers{end+1} = S.Signal; %#ok<AGROW>
end
containers{end+1} = S;
end

function value = firstNumericLocal(containers, names, defaultValue)
value = defaultValue;
for i = 1:numel(containers)
    C = containers{i};
    for j = 1:numel(names)
        name = names{j};
        if isfield(C, name) && ~isempty(C.(name)) && isnumeric(C.(name))
            value = double(C.(name));
            return;
        end
    end
end
end

function value = firstTextLocal(containers, names, defaultValue)
value = defaultValue;
for i = 1:numel(containers)
    C = containers{i};
    for j = 1:numel(names)
        name = names{j};
        if isfield(C, name) && ~isempty(C.(name)) && ...
                (ischar(C.(name)) || isstring(C.(name)))
            value = char(string(C.(name)));
            return;
        end
    end
end
end

function requireFinitePositiveLocal(values, description)
if isempty(values) || any(~isfinite(double(values))) || any(double(values) <= 0)
    error('CompareWithMeasuredData:InvalidSignalBand', ...
        '%s 必须为有限正数。', description);
end
end
