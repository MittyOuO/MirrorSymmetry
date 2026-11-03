function [RLCurve, timeAxis, aux] = ComputeRLCurveFromVoltage(y, Fs, RLParams)
% ComputeRLCurveFromVoltage
% 统一的电压/模型波形 -> RL 曲线计算函数。
%
% 用途:
%   1) 阵列合成推演模式：事件表重构得到第 i 号阵元 y_i(t) 后，计算常规 RL；
%   2) 指定阵元计算模式：保留相位事件表生成指定阵元 y_i(t) 后，计算常规 RL；
%   3) 后续实测对比或强度调节时，可复用同一套电压到声级换算逻辑。
%
% 输入:
%   y        : 输入波形，列向量或行向量。
%              默认可为模型无量纲波形，也可为电压波形，具体由 RLParams.InputMode 指定。
%   Fs       : y 的采样率，Hz，即模型处理采样率 fsSim。
%   RLParams : 参数结构体，建议字段如下：
%
%       必需/常用字段:
%       .sigMod / .SignalType      信号类型。sigMod: 1=CW,2=HFM,3=HFM_CW,4=CW_HFM,5=custom
%       .fCW                       CW 频率，Hz
%       .fStart, .fEnd             HFM 或宽带信号频率范围，Hz
%       .TpCW, .TpHFM              CW/HFM 脉冲长度，s
%       .Sensitivity               水听器灵敏度，dB re 1V/uPa，通常为负值
%       .AmpGain                   放大增益，dB
%       .NL                        噪声水平，dB，可选
%
%       输入幅值解释:
%       .InputMode                 'model' / 'voltage' / 'pressure_uPa'
%                                  'model'      : y 为无量纲模型波形，需乘系统增益；默认
%                                  'voltage'    : y 已经是水听器端电压 V
%                                  'pressure_uPa': y 是声压 uPa，需换算成电压
%       .SourceLevel               声源级 dB。InputMode='model' 时参与系统增益。
%
%       分析频带:
%       .Band                      直接指定分析频带 [fLow fHigh]，Hz，可选
%       .CWMethod                  CW 分析方法：'third_octave' 或 'engineering_narrowband'
%                                  默认 'third_octave'
%       .NarrowBandWidth           工程窄带带宽，Hz，可选
%       .CustomBand                custom 信号分析频带 [fLow fHigh]，Hz，可选
%
%       平滑与噪声:
%       .WindowSec                 滑动均方窗口长度，s，默认 0.05
%       .IncludeNoise              是否按 NL 加入理论噪声能量，默认 true
%       .UseZeroPhaseFilter        true 使用 filtfilt，false 使用 filter，默认 true
%       .FilterOrder               Butterworth 滤波器阶数，默认 4
%
% 输出:
%   RLCurve  : RL 曲线，dB re 1 uPa
%   timeAxis : 时间轴，s
%   aux      : 诊断信息结构体，包括分析频带、滤波后波形、能量项等
%
% 重要说明:
%   - 宽带信号 RL 表示分析频带内接收信号总能量，不会人为均衡各频率能量；
%   - CW 默认可采用三分之一倍频程分析，以保持与既有单频 RL 计算流程一致；
%   - 若希望更接近纯单频能量，可设置 RLParams.CWMethod='engineering_narrowband'。

    if nargin < 3
        RLParams = struct();
    end

    validateattributes(Fs, {'numeric'}, {'scalar','positive','finite'}, mfilename, 'Fs');

    y = y(:);
    n = numel(y);
    timeAxis = (0:n-1).' / Fs;

    % -----------------------------
    % 1. 读取参数
    % -----------------------------
    Sensitivity = getFieldOrDefaultLocal(RLParams, 'Sensitivity', -162);
    AmpGain     = getFieldOrDefaultLocal(RLParams, 'AmpGain', 0);
    SourceLevel = getFieldOrDefaultLocal(RLParams, 'SourceLevel', 0);
    NL          = getFieldOrDefaultLocal(RLParams, 'NL', []);

    InputMode = lower(string(getFieldOrDefaultLocal(RLParams, 'InputMode', 'model')));
    WindowSec = getFieldOrDefaultLocal(RLParams, 'WindowSec', 0.05);
    IncludeNoise = logical(getFieldOrDefaultLocal(RLParams, 'IncludeNoise', true));
    UseZeroPhaseFilter = logical(getFieldOrDefaultLocal(RLParams, 'UseZeroPhaseFilter', true));
    FilterOrder = getFieldOrDefaultLocal(RLParams, 'FilterOrder', 4);

    % -----------------------------
    % 2. 波形转换为电压 V
    % -----------------------------
    switch InputMode
        case "model"
            % y 为模型无量纲波形，复用 DisplaySimulationSignal / CompareWithMeasuredData 的系统增益逻辑。
            systemGain = 10.^((SourceLevel + Sensitivity + AmpGain) / 20);
            vSignal = y .* systemGain;

        case "voltage"
            % y 已经是水听器端电压。
            vSignal = y;

        case "pressure_upa"
            % y 为声压 uPa，换算到水听器端电压。
            systemGain = 10.^((Sensitivity + AmpGain) / 20);
            vSignal = y .* systemGain;

        otherwise
            error('RLParams.InputMode 必须为 model / voltage / pressure_uPa。');
    end

    % -----------------------------
    % 3. 决定分析频带
    % -----------------------------
    [fLow, fHigh, bandInfo] = resolveAnalysisBandLocal(RLParams, Fs);

    % -----------------------------
    % 4. 频带限定
    % -----------------------------
    [vBand, filterInfo] = applyBandLimitLocal(vSignal, Fs, fLow, fHigh, FilterOrder, UseZeroPhaseFilter);

    % -----------------------------
    % 5. 滑动均方能量
    % -----------------------------
    winLen = max(1, round(WindowSec * Fs));
    energySignal = movmean(abs(vBand).^2, winLen);
    energySignal = max(energySignal, 1e-20);

    if IncludeNoise && ~isempty(NL) && isfinite(NL)
        % 噪声声压级 -> 电压 RMS，再以不相关能量形式叠加。
        vNoiseRms = 10.^(NL / 20) .* 10.^((Sensitivity + AmpGain) / 20);
        energyNoise = vNoiseRms.^2;
    else
        vNoiseRms = 0;
        energyNoise = 0;
    end

    energyTotal = energySignal + energyNoise;
    energyTotal = max(energyTotal, 1e-20);

    % 电压能量 -> 声压级，复用旧函数逻辑：RL = 10log10(V^2) - (Sensitivity + AmpGain)
    RLCurve = 10 .* log10(energyTotal) - (Sensitivity + AmpGain);

    % -----------------------------
    % 6. 输出诊断信息
    % -----------------------------
    aux = struct();
    aux.Band = [fLow, fHigh];
    aux.BandInfo = bandInfo;
    aux.FilterInfo = filterInfo;
    aux.WindowSec = WindowSec;
    aux.WindowLength = winLen;
    aux.InputMode = char(InputMode);
    aux.vSignal = vSignal;
    aux.vBand = vBand;
    aux.energySignal = energySignal;
    aux.energyNoise = energyNoise;
    aux.energyTotal = energyTotal;
    aux.vNoiseRms = vNoiseRms;
    aux.Sensitivity = Sensitivity;
    aux.AmpGain = AmpGain;
    aux.SourceLevel = SourceLevel;
    aux.NL = NL;
end

% ========================================================================
function [fLow, fHigh, info] = resolveAnalysisBandLocal(P, Fs)
% 根据信号类型解析分析频带。

    info = struct();
    info.Method = '';
    info.Message = '';

    if isfield(P, 'Band') && ~isempty(P.Band) && numel(P.Band) == 2
        fLow = min(P.Band(:));
        fHigh = max(P.Band(:));
        info.Method = 'manual_band';
        [fLow, fHigh] = sanitizeBandLocal(fLow, fHigh, Fs);
        return;
    end

    sigMod = getFieldOrDefaultLocal(P, 'sigMod', []);
    if isempty(sigMod)
        sigType = normalizeSignalTypeKeyLocal(getFieldOrDefaultLocal(P, 'SignalType', ''));
        if strlength(sigType) == 0
            sigType = normalizeSignalTypeKeyLocal(getFieldOrDefaultLocal(P, 'sigType', ''));
        end
        switch sigType
            case "cw"
                sigMod = 1;
            case "hfm"
                sigMod = 2;
            case "hfm_cw"
                sigMod = 3;
            case "cw_hfm"
                sigMod = 4;
            case "custom"
                sigMod = 5;
            otherwise
                sigMod = 2; % 默认按宽带处理
        end
    end

    switch sigMod
        case 1  % CW
            fCW = getFieldOrDefaultLocal(P, 'fCW', []);
            if isempty(fCW) || ~isfinite(fCW) || fCW <= 0
                error('CW 信号需要提供 RLParams.fCW。');
            end

            cwMethod = lower(string(getFieldOrDefaultLocal(P, 'CWMethod', 'third_octave')));
            switch cwMethod
                case "third_octave"
                    fLow = fCW / 2^(1/6);
                    fHigh = fCW * 2^(1/6);
                    info.Method = 'cw_third_octave';

                case "engineering_narrowband"
                    TpCW = getFieldOrDefaultLocal(P, 'TpCW', 0.2);
                    bw = getFieldOrDefaultLocal(P, 'NarrowBandWidth', []);
                    if isempty(bw) || ~isfinite(bw) || bw <= 0
                        bw = max(5, 2 / max(TpCW, eps));
                    end
                    fLow = fCW - bw/2;
                    fHigh = fCW + bw/2;
                    info.Method = 'cw_engineering_narrowband';
                    info.NarrowBandWidth = bw;

                otherwise
                    error('未知 CWMethod：%s。可选 third_octave / engineering_narrowband。', cwMethod);
            end

        case 2  % HFM
            fStart = getFieldOrDefaultLocal(P, 'fStart', []);
            fEnd = getFieldOrDefaultLocal(P, 'fEnd', []);
            [fStart, fEnd] = inferBandFromCenterBandwidthLocal(P, fStart, fEnd);
            if isempty(fStart) || isempty(fEnd) || ~isfinite(fStart) || ~isfinite(fEnd)
                error('HFM 信号需要提供 RLParams.fStart 与 RLParams.fEnd。');
            end
            fLow = min(fStart, fEnd);
            fHigh = max(fStart, fEnd);
            info.Method = 'hfm_signal_band';

        case {3,4}  % HFM+CW / CW+HFM
            fStart = getFieldOrDefaultLocal(P, 'fStart', []);
            fEnd = getFieldOrDefaultLocal(P, 'fEnd', []);
            fCW = getFieldOrDefaultLocal(P, 'fCW', []);
            [fStart, fEnd] = inferBandFromCenterBandwidthLocal(P, fStart, fEnd);
            if isempty(fCW) || ~isfinite(fCW) || fCW <= 0
                fCW = getFieldOrDefaultLocal(P, 'f0', []);
            end
            if isempty(fStart) || isempty(fEnd) || isempty(fCW) || ...
                    ~isfinite(fStart) || ~isfinite(fEnd) || ~isfinite(fCW) || fCW <= 0
                error('组合信号需要同时提供 RLParams.fStart、RLParams.fEnd 与 RLParams.fCW。');
            end
            bandFreqs = [fStart, fEnd, fCW];
            fLow = min(bandFreqs);
            fHigh = max(bandFreqs);
            info.Method = 'combined_signal_union_band';

        case 5  % custom
            if isfield(P, 'CustomBand') && ~isempty(P.CustomBand) && numel(P.CustomBand) == 2
                fLow = min(P.CustomBand(:));
                fHigh = max(P.CustomBand(:));
                info.Method = 'custom_manual_band';
            elseif isfield(P, 'fStart') && isfield(P, 'fEnd') && ~isempty(P.fStart) && ~isempty(P.fEnd)
                fLow = min(P.fStart, P.fEnd);
                fHigh = max(P.fStart, P.fEnd);
                info.Method = 'custom_from_fStart_fEnd';
            else
                fLow = max(1, 0.01 * Fs);
                fHigh = 0.45 * Fs;
                info.Method = 'custom_default_wideband';
                info.Message = 'custom 信号未指定分析频带，默认使用 [0.01Fs, 0.45Fs]。';
            end

        otherwise
            error('未知 sigMod：%g。', sigMod);
    end

    [fLow, fHigh] = sanitizeBandLocal(fLow, fHigh, Fs);
end

% ========================================================================
function key = normalizeSignalTypeKeyLocal(sigType)
    key = lower(strtrim(string(sigType)));
    key = replace(key, "窄带", "");
    key = replace(key, "宽带", "");
    key = replace(key, "+", "_");
    key = replace(key, "-", "_");
    key = replace(key, " ", "");
end

% ========================================================================
function [fStart, fEnd] = inferBandFromCenterBandwidthLocal(P, fStart, fEnd)
    if ~isempty(fStart) && ~isempty(fEnd) && isfinite(fStart) && isfinite(fEnd)
        return;
    end

    f0 = getFieldOrDefaultLocal(P, 'f0', []);
    B = getFieldOrDefaultLocal(P, 'B', []);

    if isempty(f0) || isempty(B) || ~isfinite(f0) || ~isfinite(B) || B <= 0
        return;
    end

    fStart = max(eps, double(f0) - double(B) / 2);
    fEnd = double(f0) + double(B) / 2;
end

% ========================================================================
function [fLow, fHigh] = sanitizeBandLocal(fLow, fHigh, Fs)
% 限制频带在 (0, Nyquist) 内，避免滤波器失败。

    nyq = Fs / 2;
    fLow = max(fLow, max(0.5, 1e-6 * Fs));
    fHigh = min(fHigh, nyq * 0.98);

    if fHigh <= fLow
        error('分析频带无效：[%.3f, %.3f] Hz，Fs=%.3f Hz。', fLow, fHigh, Fs);
    end
end

% ========================================================================
function [yBand, info] = applyBandLimitLocal(y, Fs, fLow, fHigh, order, useZeroPhase)
% Butterworth 带通滤波。若频带接近全带宽，也仍执行带通以保持定义一致。

    info = struct();
    info.FilterApplied = true;
    info.FilterOrder = order;
    info.UseZeroPhaseFilter = useZeroPhase;

    Wn = [fLow, fHigh] / (Fs/2);
    Wn(1) = max(Wn(1), eps);
    Wn(2) = min(Wn(2), 0.999);

    if Wn(2) <= Wn(1)
        error('归一化滤波频带无效：[%.6f, %.6f]。', Wn(1), Wn(2));
    end

    [b, a] = butter(order, Wn, 'bandpass');

    if useZeroPhase && numel(y) > 3 * max(numel(a), numel(b))
        yBand = filtfilt(b, a, y);
        info.FilterType = 'butter_bandpass_filtfilt';
    else
        yBand = filter(b, a, y);
        info.FilterType = 'butter_bandpass_filter';
    end
end

% ========================================================================
function val = getFieldOrDefaultLocal(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        val = S.(fieldName);
    else
        val = defaultVal;
    end
end
