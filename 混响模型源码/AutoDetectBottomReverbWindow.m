function [EvalWindow, Info] = AutoDetectBottomReverbWindow(RLMeas, RLSim, timeAxis, varargin)
% AutoDetectBottomReverbWindow
% 自动检测第一个海底反射峰，并返回评价时间窗
%
% 当前规则:
%   1. 最大峰视为直达波；
%   2. 跳过直达波后的保护时间 DirectGuardSec；
%   3. 在之后搜索第一个显著峰，作为海底反射峰；
%   4. 从该峰开始，向后取 EvalDurationSec 秒。
%   指标选窗传AuditSimulation=false：只检测实测RL，不依赖仿真峰形。

p = inputParser;

addParameter(p, 'SmoothWindowSec', 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'DirectGuardSec', 1.2, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'PeakProminenceDB', 6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'NoiseMarginDB', 6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'EvalDurationSec', 40, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'AuditSimulation', true, @(x) islogical(x) && isscalar(x));

parse(p, varargin{:});

SmoothWindowSec  = p.Results.SmoothWindowSec;
DirectGuardSec   = p.Results.DirectGuardSec;
PeakProminenceDB = p.Results.PeakProminenceDB;
NoiseMarginDB    = p.Results.NoiseMarginDB;
EvalDurationSec  = p.Results.EvalDurationSec;
AuditSimulation = p.Results.AuditSimulation;

RLMeas = real(RLMeas(:));
RLSim  = real(RLSim(:));
timeAxis = timeAxis(:);

if AuditSimulation
    N = min([length(RLMeas), length(RLSim), length(timeAxis)]);
else
    N = min([length(RLMeas), length(timeAxis)]);
end
RLMeas = RLMeas(1:N);
if AuditSimulation, RLSim = RLSim(1:N); end
timeAxis = timeAxis(1:N);

% 评价起点始终由实测B1决定，不能对实测和仿真取逐点最大值。
% AuditSimulation=true时另行检测仿真B1以审计残差；false时完全跳过
% 仿真峰值检测。两种情况都不移动曲线，沿用外部B1共同对齐。
[~, measuredPeakInfo] = DetectFirstBottomPeak(RLMeas, timeAxis, ...
    'SmoothWindowSec', SmoothWindowSec, ...
    'DirectGuardSec', DirectGuardSec, ...
    'PeakProminenceDB', PeakProminenceDB, ...
    'NoiseMarginDB', NoiseMarginDB);
simulatedPeakInfo = struct();
if AuditSimulation
    [~, simulatedPeakInfo] = DetectFirstBottomPeak(RLSim, timeAxis, ...
        'SmoothWindowSec', SmoothWindowSec, ...
        'DirectGuardSec', DirectGuardSec, ...
        'PeakProminenceDB', PeakProminenceDB, ...
        'NoiseMarginDB', NoiseMarginDB);
end

firstBottomPeakTime = measuredPeakInfo.FirstBottomPeakTimeSec;
firstBottomPeakValue = measuredPeakInfo.FirstBottomPeakValueDB;
method = 'IndependentFirstBottomPeaks';
if ~AuditSimulation, method = 'MeasuredRLOnly'; end
noiseFloor = measuredPeakInfo.NoiseFloorDB;
idxDirect = measuredPeakInfo.DirectIndex;
tDirect = measuredPeakInfo.DirectTimeSec;
directPeakValue = measuredPeakInfo.DirectPeakValueDB;
idxSearchStart = measuredPeakInfo.SearchStartIndex;

tStart = firstBottomPeakTime;
tEnd = min(tStart + EvalDurationSec, timeAxis(end));

EvalWindow = [tStart, tEnd];

Info = struct();

Info.Method = method;
Info.NoiseFloor = noiseFloor;

Info.DirectTime = tDirect;
Info.DirectPeakValue = directPeakValue;
Info.DirectIndex = idxDirect;

Info.SearchStartTime = timeAxis(idxSearchStart);

Info.FirstBottomPeakTime = firstBottomPeakTime;
Info.FirstBottomPeakValue = firstBottomPeakValue;
Info.MeasuredPeak = measuredPeakInfo;
Info.SimulatedPeak = simulatedPeakInfo;
Info.WindowReference = 'MeasuredRL';
Info.SimulationAuditPerformed = AuditSimulation;
Info.SimulatedFirstBottomPeakTime = NaN;
Info.ResidualB1OffsetSec = NaN;
if AuditSimulation
    Info.SimulatedFirstBottomPeakTime = simulatedPeakInfo.FirstBottomPeakTimeSec;
    Info.ResidualB1OffsetSec = simulatedPeakInfo.FirstBottomPeakTimeSec - firstBottomPeakTime;
end

Info.EvalStart = tStart;
Info.EvalEnd = tEnd;
Info.EvalDurationSec = tEnd - tStart;

Info.SmoothWindowSec = SmoothWindowSec;
Info.DirectGuardSec = DirectGuardSec;
Info.PeakProminenceDB = PeakProminenceDB;
Info.NoiseMarginDB = NoiseMarginDB;

end
