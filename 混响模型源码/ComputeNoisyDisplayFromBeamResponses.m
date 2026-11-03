function [vTotalNoisy,RLDisplay,NoiseInfo] = ...
        ComputeNoisyDisplayFromBeamResponses(yDir,ySca,cfg,thetaList,startCaseIndex)
%ComputeNoisyDisplayFromBeamResponses Display-only noisy voltage and RL.
% Old complex clean beam responses and deterministic result.RL are untouched.
if nargin<5, startCaseIndex=1; end
validateattributes(startCaseIndex,{'numeric'},{'scalar','integer','positive'});
if ~isequal(size(yDir),size(ySca)) || size(yDir,1) ~= numel(thetaList)
    error('ComputeNoisyDisplayFromBeamResponses:ShapeMismatch', ...
        'yDir/ySca must match thetaList in theta-by-time orientation.');
end
fs = double(cfg.Simulation.fsSim);
sl = double(cfg.Intensity.sourceLevel);
sensitivity = double(cfg.Intensity.sensitivity);
gain = double(cfg.Intensity.ampGain);
nl = double(cfg.Intensity.environmentNoise);
nCase = size(yDir,1);
nTime = size(yDir,2);
vTotalNoisy = zeros(nCase,nTime);
RLDisplay = zeros(nCase,nTime);
NoiseInfoCell = cell(nCase,1);
systemGain = 10^((sl+sensitivity+gain)/20);
windowSize = max(1,round(0.05*fs));
for k = 1:nCase
    caseIndex = startCaseIndex + k - 1;
    seed = mod(20260928 + 104729*(caseIndex-1) + ...
        round((double(thetaList(k))+180)*1000), 2^32-1);
    [vNoise,~,info] = BuildFluctuatingEnvironmentalNoise( ...
        nTime,fs,nl,sensitivity,gain,3.5,seed);
    cleanVoltage = real((yDir(k,:)+ySca(k,:))*systemGain);
    vTotalNoisy(k,:) = cleanVoltage + vNoise.';
    energy = movmean(vTotalNoisy(k,:).^2,windowSize,2);
    RLDisplay(k,:) = 10*log10(max(energy,realmin('double'))) - ...
        (sensitivity+gain);
    info.ThetaDeg = double(thetaList(k));
    info.CaseIndex = caseIndex;
    NoiseInfoCell{k} = info;
end
NoiseInfo = vertcat(NoiseInfoCell{:});
end
