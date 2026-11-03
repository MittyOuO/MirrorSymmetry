function [Metrics] = ComputeValidationMetrics(vMeasFiltered, RLMeas, vSimTotal, RLSim, timeAxis, varargin)
% ComputeValidationMetrics
% 计算实测信号与仿真信号之间的验收验证指标
%
% 当前版本:
%   1. PDF 分布相似性：Hilbert 包络 + RMS 归一化 + Bhattacharyya 系数
%   2. 混响强度时域波形相关性：Hilbert 包络 + 滑动平均；沿用外部B1共同对齐，不二次平移
%   3. 均方根误差准确度：使用 RL 曲线 RLSim/RLMeas 计算，避免随机噪声电压逐点误差
%   4. 方位历程图峰值到达时间误差：当前单通道数据暂保留接口

% ============================================================
% 0. 参数解析
% ============================================================
p = inputParser;

addParameter(p, 'EvalWindow', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
addParameter(p, 'AutoWindow', true, @(x) islogical(x) || isnumeric(x));
% 正式模式为 DirectPeak/DirectEnd；FirstBottomPeak 仅保留历史兼容。
addParameter(p, 'EvalStartMode', 'DirectPeak', ...
    @(x) (ischar(x) && isrow(x)) || (isstring(x) && isscalar(x)));
addParameter(p, 'FsComp', [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
addParameter(p, 'SignalSpec', struct(), @(x) isstruct(x) && isscalar(x));

% 从第一个海底反射峰开始，默认向后取 40 s
addParameter(p, 'EvalDurationSec', 40, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));

% PDF 和包络相关参数
addParameter(p, 'NumBins', 80, @(x) isnumeric(x) && isscalar(x) && x > 5);
addParameter(p, 'SmoothWindowSec', 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0);

% 自动检测参数
addParameter(p, 'DirectGuardSec', 1.2, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'PeakProminenceDB', 6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'NoiseMarginDB', 6, @(x) isnumeric(x) && isscalar(x) && x > 0);

% 兼容旧调用参数，但指标函数不再执行任意相关性二次平移。
% 对齐必须在进入本函数前按第二峰（第一海底反射峰B1）共同完成。
addParameter(p, 'EnableLagAlign', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'MaxLagSec', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'LagAlignReference', 'FirstBottomPeak', @(x) ischar(x) || isstring(x));
addParameter(p, 'AlignmentInfo', struct(), @(x) isstruct(x) && isscalar(x));

% 是否打印
addParameter(p, 'Verbose', true, @(x) islogical(x) || isnumeric(x));

parse(p, varargin{:});

EvalWindow       = p.Results.EvalWindow;
AutoWindow       = logical(p.Results.AutoWindow);
EvalStartMode    = validatestring(p.Results.EvalStartMode, ...
    {'DirectPeak','DirectEnd','FirstBottomPeak'});
FsComp           = p.Results.FsComp;
SignalSpec       = p.Results.SignalSpec;
EvalDurationSec  = p.Results.EvalDurationSec;
NumBins          = p.Results.NumBins;
SmoothWindowSec  = p.Results.SmoothWindowSec;
DirectGuardSec   = p.Results.DirectGuardSec;
PeakProminenceDB = p.Results.PeakProminenceDB;
NoiseMarginDB    = p.Results.NoiseMarginDB;
EnableLagAlign   = logical(p.Results.EnableLagAlign);
MaxLagSec        = p.Results.MaxLagSec;
LagAlignReference = char(p.Results.LagAlignReference);
AlignmentInfo    = p.Results.AlignmentInfo;
Verbose          = logical(p.Results.Verbose);

% ============================================================
% 1. 数据整理与共同采样率/长度合同
% ============================================================
if isempty(FsComp)
    error('ComputeValidationMetrics:MissingFsComp', ...
        '正式指标调用必须显式提供 FsComp。');
end
if ~isvector(vMeasFiltered) || ~isvector(vSimTotal) || ...
        ~isvector(RLMeas) || ~isvector(RLSim) || ~isvector(timeAxis)
    error('ComputeValidationMetrics:InvalidShape', ...
        '五个时间序列均必须为向量。');
end
vMeasFiltered = real(vMeasFiltered(:));
vSimTotal     = real(vSimTotal(:));
RLMeas        = real(RLMeas(:));
RLSim         = real(RLSim(:));
timeAxis      = timeAxis(:);

lengths = [numel(vMeasFiltered),numel(vSimTotal),numel(RLMeas), ...
    numel(RLSim),numel(timeAxis)];
if any(lengths ~= lengths(1)) || lengths(1) < 10
    error('ComputeValidationMetrics:LengthMismatch', ...
        'vMeas/vSim/RLMeas/RLSim/timeAxis 必须同长度且至少 10 点：%s', mat2str(lengths));
end
if any(~isfinite(timeAxis)) || any(diff(timeAxis) <= 0)
    error('ComputeValidationMetrics:InvalidTimeAxis', ...
        'timeAxis 必须有限且严格递增。');
end
fsFromTimeAxis = 1/median(diff(timeAxis));
FsCompRelativeError = abs(fsFromTimeAxis-FsComp)/FsComp;
if FsCompRelativeError > 1e-4
    error('ComputeValidationMetrics:FsCompMismatch', ...
        'timeAxis 采样率 %.9g Hz 与 FsComp %.9g Hz 不一致。', fsFromTimeAxis, FsComp);
end
N = lengths(1); %#ok<NASGU>
fs = FsComp;
smoothPts = max(3, round(SmoothWindowSec * fs));

% ============================================================
% 2. 自动确定评价时间窗
% ============================================================
WindowInfo = struct();

if isempty(EvalWindow) && AutoWindow
    if strcmp(EvalStartMode, 'FirstBottomPeak')
        % Legacy only: formal calls use measured-voltage DirectPeak/DirectEnd.
        [EvalWindow, WindowInfo] = AutoDetectBottomReverbWindow( ...
            RLMeas, [], timeAxis, ...
            'AuditSimulation', false, ...
            'SmoothWindowSec', SmoothWindowSec, ...
            'DirectGuardSec', DirectGuardSec, ...
            'PeakProminenceDB', PeakProminenceDB, ...
            'NoiseMarginDB', NoiseMarginDB, ...
            'EvalDurationSec', EvalDurationSec);
    else
        DirectInfo = DetectDirectWaveSupport( ...
            vMeasFiltered, timeAxis, FsComp, SignalSpec);
        WindowInfo = DirectInfo;
        WindowInfo.Method = 'MeasuredVoltageDirectSupport';
        if strcmp(EvalStartMode, 'DirectEnd') && ~DirectInfo.DirectSupportReliable
            Metrics = notComputedMetricsLocal( ...
                ['DirectEnd NOT_COMPUTED: ',DirectInfo.DirectFailureReason], ...
                DirectInfo,FsComp,fsFromTimeAxis,FsCompRelativeError,EvalStartMode);
            return;
        end
        if strcmp(EvalStartMode, 'DirectPeak') && ...
                (~isfinite(DirectInfo.DirectPeakTime) || ...
                 DirectInfo.PeakToBackgroundRatio_dB < 6)
            Metrics = notComputedMetricsLocal( ...
                ['DirectPeak NOT_COMPUTED: ',DirectInfo.DirectFailureReason], ...
                DirectInfo,FsComp,fsFromTimeAxis,FsCompRelativeError,EvalStartMode);
            return;
        end
        if strcmp(EvalStartMode, 'DirectPeak')
            evalStart = DirectInfo.DirectPeakTime;
        else
            evalStart = DirectInfo.DirectEndTime;
        end
        EvalWindow = [evalStart, min(evalStart+EvalDurationSec,timeAxis(end))];
    end
    WindowInfo.EvalStartMode = EvalStartMode;
    WindowInfo.IncludeDirectWave = strcmp(EvalStartMode, 'DirectPeak');

elseif isempty(EvalWindow)
    EvalWindow = [timeAxis(1), min(timeAxis(1) + EvalDurationSec, timeAxis(end))];
    WindowInfo.Method = 'DefaultFromStart';
    WindowInfo.EvalStartMode = 'RecordStart';
    WindowInfo.IncludeDirectWave = [];
else
    WindowInfo.Method = 'Manual';
    WindowInfo.EvalStart = EvalWindow(1);
    WindowInfo.EvalEnd = EvalWindow(2);
    WindowInfo.EvalDurationSec = EvalWindow(2) - EvalWindow(1);
    WindowInfo.EvalStartMode = 'Manual';
    WindowInfo.IncludeDirectWave = []; % 手动窗是否覆盖直达波由调用者决定。
end
WindowInfo.EvalStart = EvalWindow(1);
WindowInfo.EvalEnd = EvalWindow(2);
WindowInfo.EvalDurationSec = EvalWindow(2) - EvalWindow(1);

idxEval = timeAxis >= EvalWindow(1) & timeAxis <= EvalWindow(2);

idxValid = idxEval ...
    & isfinite(vMeasFiltered) ...
    & isfinite(vSimTotal) ...
    & isfinite(RLMeas) ...
    & isfinite(RLSim);

vMeas = vMeasFiltered(idxValid);
vSim  = vSimTotal(idxValid);
rlMeas = RLMeas(idxValid);
rlSim  = RLSim(idxValid);
tEval  = timeAxis(idxValid);

if numel(vMeas) < 10
    error('有效评价样本数过少，请检查自动检测窗口或手动设置 EvalWindow。');
end

% ============================================================
% 3. 计算包络与平滑曲线
% ============================================================
envMeas = abs(hilbert(vMeas));
envSim  = abs(hilbert(vSim));

envMeasSmooth0 = movmean(envMeas, smoothPts);
envSimSmooth0  = movmean(envSim,  smoothPts);

rlMeasSmooth0 = movmean(rlMeas, smoothPts);
rlSimSmooth0  = movmean(rlSim,  smoothPts);

% ============================================================
% 4. 对齐审计：禁止指标函数内部再次平移
% ============================================================
% 绘图与指标必须使用同一组、已经按B1共同平移的数据。即便旧调用仍传入
% EnableLagAlign=true，也只发出告警而不调用 BestLagAlign/ApplyKnownLag。
if EnableLagAlign || MaxLagSec > 0
    warning('ComputeValidationMetrics:LegacyLagAlignDisabled', ...
        ['指标内部任意相关性精对齐已停用；当前数据仅沿用外部第一海底反射峰' ...
         '（B1）共同对齐。']);
end
lagPts = fieldOrLocal(AlignmentInfo, 'LagPoints', 0);
lagSec = fieldOrLocal(AlignmentInfo, 'LagSec', 0);
lagCorr = NaN;
envMeasSmooth = envMeasSmooth0;
envSimSmooth  = envSimSmooth0;
rlMeasSmooth = rlMeasSmooth0;
rlSimSmooth  = rlSimSmooth0;

% ============================================================
% 5. 指标一：PDF 分布相似性
% ============================================================
% 按文档：Hilbert 包络，RMS 归一化，仅比较概率分布形状。
% 注意：历史字段名沿用 pdfMeas/pdfSim，但 histcounts 使用
% Normalization='probability'，因此保存的是共同分箱上的离散概率质量
% （不是除以 bin 宽度后的连续概率密度）。共同上界取合并样本的
% 99.5% 分位数，超出上界的极端尾部不进入直方图且不再次归一化，
% 因此 sum(pdfMeas/pdfSim) 表示各自的保留概率质量，通常接近但不必等于1。

envMeasPDF = envMeas ./ max(rms(envMeas), eps);
envSimPDF  = envSim  ./ max(rms(envSim), eps);

allEnv = [envMeasPDF; envSimPDF];

lowEdge = 0;
highEdge = prctile(allEnv, 99.5);

if highEdge <= lowEdge || ~isfinite(highEdge)
    highEdge = max(allEnv);
end

edges = linspace(lowEdge, highEdge, NumBins + 1);

pMeas = histcounts(envMeasPDF, edges, 'Normalization', 'probability');
pSim  = histcounts(envSimPDF,  edges, 'Normalization', 'probability');

pMeas = pMeas(:);
pSim  = pSim(:);

PDF_BC = sum(sqrt(pMeas .* pSim));
PDF_BC = min(max(PDF_BC, 0), 1);

% ============================================================
% 6. 指标二：混响强度时域波形相关性
% ============================================================
% 按文档：Hilbert 包络，滑动平均，计算平滑包络相关系数。

if std(envMeasSmooth) < eps || std(envSimSmooth) < eps
    EnvelopeCorr = NaN;
else
    C = corrcoef(envMeasSmooth, envSimSmooth);
    EnvelopeCorr = C(1, 2);
end

% 参考项：RL 曲线相关性
if std(rlMeasSmooth) < eps || std(rlSimSmooth) < eps
    RLCorr = NaN;
else
    Crl = corrcoef(rlMeasSmooth, rlSimSmooth);
    RLCorr = Crl(1, 2);
end

% ============================================================
% 7. 指标三：RL 曲线均方根误差准确度
% ============================================================
% 根据你的工程验收选择:
%   使用 RLSim/RLMeas 作为 S_i/M_i；
%   每一个 i 对应同一时间轴上的 RL 采样点；
%   避免加随机噪声后的电压信号逐点 RMSE 不可解释。

S = rlSim;
M = rlMeas;

RMSE_RL = sqrt(mean((S - M).^2));
sigmaM_RL = sqrt(mean(M.^2));

Accuracy_RL = (1 - RMSE_RL / max(sigmaM_RL, eps)) * 100;
Accuracy_RL = max(min(Accuracy_RL, 100), -Inf);

% 参考项：如果仍想观察原始电压逐点 Accuracy，可以保留但不作为正式判据
RMSE_VoltageRef = sqrt(mean((vSim - vMeas).^2));
sigmaM_VoltageRef = sqrt(mean(vMeas.^2));
Accuracy_VoltageRef = (1 - RMSE_VoltageRef / max(sigmaM_VoltageRef, eps)) * 100;
Accuracy_VoltageRef = max(min(Accuracy_VoltageRef, 100), -Inf);

% ============================================================
% 8. 方位历程图可见峰值到达时间误差接口
% ============================================================
PeakArrivalError = NaN;
PeakArrivalStatus = '未计算：当前输入为单通道时域信号，缺少 BTR/多波束方位历程图数据。';

% ============================================================
% 9. 打包输出
% ============================================================
Metrics = struct();
Metrics.Available = true;
Metrics.Status = 'COMPUTED';
Metrics.FsComp = FsComp;
Metrics.EnvelopeSampleRateHz = fsFromTimeAxis;
Metrics.FsCompRelativeError = FsCompRelativeError;

Metrics.PDF_BC = PDF_BC;
Metrics.EnvelopeCorr = EnvelopeCorr;
Metrics.RLCorr = RLCorr;

% 正式 Accuracy 指标：RL 曲线版本
Metrics.RMSE_RL = RMSE_RL;
Metrics.SigmaM_RL = sigmaM_RL;
Metrics.Accuracy_RL = Accuracy_RL;

% 参考项
Metrics.RMSE_VoltageRef = RMSE_VoltageRef;
Metrics.SigmaM_VoltageRef = sigmaM_VoltageRef;
Metrics.Accuracy_VoltageRef = Accuracy_VoltageRef;

Metrics.PeakArrivalError = PeakArrivalError;
Metrics.PeakArrivalStatus = PeakArrivalStatus;

Metrics.Threshold.PDF_BC = 0.80;
Metrics.Threshold.EnvelopeCorr = 0.85;
Metrics.Threshold.Accuracy = 80;

Metrics.Pass.PDF_BC = PDF_BC >= Metrics.Threshold.PDF_BC;
Metrics.Pass.EnvelopeCorr = EnvelopeCorr >= Metrics.Threshold.EnvelopeCorr;
Metrics.Pass.Accuracy_RL = Accuracy_RL >= Metrics.Threshold.Accuracy;
Metrics.Pass.PeakArrivalError = false;

Metrics.EvalWindow = [tEval(1), tEval(end)];
Metrics.NumSamples = numel(tEval);
Metrics.SmoothWindowSec = SmoothWindowSec;
Metrics.NumBins = NumBins;
Metrics.WindowInfo = WindowInfo;
Metrics.EvalStartMode = WindowInfo.EvalStartMode;
Metrics.IncludeDirectWave = WindowInfo.IncludeDirectWave;

Metrics.LagAlign.Enable = false;
Metrics.LagAlign.LegacyRequested = EnableLagAlign || MaxLagSec > 0;
Metrics.LagAlign.AppliedInsideMetrics = false;
Metrics.LagAlign.Reference = 'FirstBottomPeak';
Metrics.LagAlign.RequestedReference = LagAlignReference;
Metrics.LagAlign.MaxLagSec = 0;
Metrics.LagAlign.LagPts = lagPts;
Metrics.LagAlign.LagSec = lagSec;
Metrics.LagAlign.BestCorr = lagCorr;
Metrics.LagAlign.Method = fieldOrLocal(AlignmentInfo, 'Method', ...
    'external_first_bottom_peak');
Metrics.Alignment = AlignmentInfo;

Metrics.Curve.timeAxis = tEval;

Metrics.Curve.vMeas = vMeas;
Metrics.Curve.vSim = vSim;

Metrics.Curve.RLMeas = rlMeas;
Metrics.Curve.RLSim = rlSim;

Metrics.Curve.envMeas = envMeas;
Metrics.Curve.envSim = envSim;
Metrics.Curve.envMeasSmooth = envMeasSmooth;
Metrics.Curve.envSimSmooth = envSimSmooth;

Metrics.Curve.rlMeasSmooth = rlMeasSmooth;
Metrics.Curve.rlSimSmooth = rlSimSmooth;

Metrics.Curve.pdfEdges = edges;
Metrics.Curve.pdfMeas = pMeas;
Metrics.Curve.pdfSim = pSim;

if Verbose
    PrintValidationMetrics(Metrics);
end

function M = notComputedMetricsLocal(reason, WindowInfo, FsComp, fsFromAxis, relativeError, mode)
M = struct();
M.Available = false;
M.Status = 'NOT_COMPUTED';
M.Reason = reason;
M.FsComp = FsComp;
M.EnvelopeSampleRateHz = fsFromAxis;
M.FsCompRelativeError = relativeError;
M.WindowInfo = WindowInfo;
M.EvalStartMode = mode;
M.IncludeDirectWave = strcmp(mode,'DirectPeak');
M.EvalWindow = [NaN NaN];
M.NumSamples = 0;
M.PDF_BC = NaN;
M.EnvelopeCorr = NaN;
M.RLCorr = NaN;
M.Accuracy_RL = NaN;
M.PeakArrivalError = NaN;
M.PeakArrivalStatus = 'NOT_COMPUTED';
M.Threshold = struct('PDF_BC',0.80,'EnvelopeCorr',0.85,'Accuracy',80);
M.Pass = struct('PDF_BC',false,'EnvelopeCorr',false, ...
    'Accuracy_RL',false,'PeakArrivalError',false);
M.LagAlign = struct('Enable',false,'AppliedInsideMetrics',false, ...
    'MaxLagSec',0);
M.Curve = struct();
end

function value = fieldOrLocal(S, name, defaultValue)
% 读取可选审计字段；缺失时保持向后兼容。
if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
    value = S.(name);
else
    value = defaultValue;
end
end

end
