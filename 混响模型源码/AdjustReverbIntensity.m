function [Adjusted, AdjustInfo] = AdjustReverbIntensity(ResultsBase, InputParams, AdjustParams)
% AdjustReverbIntensity
% 对已完成的混响结果进行后处理强度调节，不重新计算混响传播/散射。
%
% 用途：
%   1) RunMode=1/2 的时域相干波形：按 SL、灵敏度、放大增益换算为水听器端电压；
%   2) 统一调用 ComputeRLCurveFromVoltage，将调节后的电压波形换算为 RL 曲线；
%   3) RunMode=2 若存在 FastInfo.IRTotal，则按平均能量叠加原理重算快速 RL。
%
% 输入：
%   ResultsBase  : RunReverbSimulation 输出结果，建议为未做强度后处理的基准结果。
%   InputParams  : 运行时输入参数。
%   AdjustParams : 调节参数结构体：
%       .SourceLevel / .SL      声源级，dB
%       .Sensitivity            水听器灵敏度，dB re 1V/uPa
%       .AmpGain                放大增益，dB
%       .NL                     环境噪声级，dB re 1uPa
%       .RunMode                1/2，可选；默认从 ResultsBase/InputParams 读取
%       .WindowSec              RL 平滑窗口，默认 0.05 s
%       .SignalType/sigMod      信号类型，可选
%       .f0/.B/.fCW/.fStart/.fEnd 分析频带参数，可选
%
% 输出：
%   Adjusted : 调节后的结果，包括 vTotal、RLFromVoltage、RLFastAdjusted 等。
%   AdjustInfo : 调节参数和诊断信息。

    if nargin < 2 || isempty(InputParams)
        InputParams = struct();
    end
    if nargin < 3 || isempty(AdjustParams)
        AdjustParams = struct();
    end

    RunMode = getFieldOrDefaultLocal(AdjustParams, 'RunMode', ...
              getFieldOrDefaultLocal(ResultsBase, 'RunMode', getFieldOrDefaultLocal(InputParams, 'RunMode', 1)));

    SL = getFieldOrDefaultLocal(AdjustParams, 'SourceLevel', getFieldOrDefaultLocal(AdjustParams, 'SL', ...
         getFieldOrDefaultLocal(InputParams, 'SourceLevel', getFieldOrDefaultLocal(InputParams, 'SL', 220))));
    Sensitivity = getFieldOrDefaultLocal(AdjustParams, 'Sensitivity', ...
                  getFieldOrDefaultLocal(InputParams, 'HydrophoneSensitivity', -162));
    AmpGain = getFieldOrDefaultLocal(AdjustParams, 'AmpGain', getFieldOrDefaultLocal(InputParams, 'AmpGain', 20));
    NL = getFieldOrDefaultLocal(AdjustParams, 'NL', getFieldOrDefaultLocal(InputParams, 'NL', 57));

    Fs = getFieldOrDefaultLocal(InputParams, 'fs', getFieldOrDefaultLocal(ResultsBase, 'fs', []));
    if isempty(Fs) || ~isfinite(Fs) || Fs <= 0
        error('AdjustReverbIntensity:InvalidFs', '无法读取有效采样率 Fs。');
    end

    % ------------------------------------------------------------------
    % 1. 时域保相波形强度调节：模型无量纲波形 -> 水听器端电压
    % ------------------------------------------------------------------
    yModel = [];
    if isfield(ResultsBase, 'yTotal') && ~isempty(ResultsBase.yTotal)
        yModel = ResultsBase.yTotal(:);
    elseif isfield(ResultsBase, 'yDir') && isfield(ResultsBase, 'ySca') && ~isempty(ResultsBase.yDir) && ~isempty(ResultsBase.ySca)
        yModel = ResultsBase.yDir(:) + ResultsBase.ySca(:);
    end

    Adjusted = struct();
    Adjusted.RunMode = RunMode;
    Adjusted.SourceLevel = SL;
    Adjusted.Sensitivity = Sensitivity;
    Adjusted.AmpGain = AmpGain;
    Adjusted.NL = NL;
    Adjusted.fs = Fs;

    systemGain = 10.^((SL + Sensitivity + AmpGain) ./ 20);
    Adjusted.SystemGain = systemGain;

    if ~isempty(yModel)
        vTotal = yModel .* systemGain;
        Adjusted.vTotal = real(vTotal(:));
        Adjusted.timeVoltage = (0:numel(vTotal)-1).' ./ Fs;

        RLParams = buildRLParamsLocal(InputParams, AdjustParams, SL, Sensitivity, AmpGain, NL);
        RLParams.InputMode = 'voltage';
        RLParams.SourceLevel = 0;       % 已换算为电压，避免重复乘声源级
        RLParams.IncludeNoise = true;   % RL 中以能量形式叠加 NL

        [RLCurve, timeRL, auxRL] = ComputeRLCurveFromVoltage(vTotal, Fs, RLParams);
        Adjusted.RLFromVoltage = RLCurve(:);
        Adjusted.timeRL = timeRL(:);
        Adjusted.RLAux = auxRL;
    else
        Adjusted.vTotal = [];
        Adjusted.timeVoltage = [];
        Adjusted.RLFromVoltage = [];
        Adjusted.timeRL = [];
        Adjusted.RLAux = struct();
    end

    % ------------------------------------------------------------------
    % 2. RunMode=2 快速 RL 强度调节：IR 能量 + 噪声能量
    % ------------------------------------------------------------------
    Adjusted.RLFastAdjusted = [];
    Adjusted.timeFast = [];
    Adjusted.FastAux = struct();

    if RunMode == 2
        [IRTotal, timeFast, fastSource] = getFastIRTotalLocal(ResultsBase, SL, NL);
        if ~isempty(IRTotal)
            signalEnergyFast = 10.^(SL ./ 10) .* max(real(IRTotal(:)), 0);
            if isfinite(NL)
                noiseEnergyFast = 10.^(NL ./ 10);
            else
                noiseEnergyFast = 0;
            end
            RLFastAdjusted = 10 .* log10(max(signalEnergyFast + noiseEnergyFast, realmin));
            Adjusted.RLFastAdjusted = RLFastAdjusted(:);
            Adjusted.timeFast = timeFast(:);
            Adjusted.FastAux.SignalEnergy = signalEnergyFast(:);
            Adjusted.FastAux.NoiseEnergy = noiseEnergyFast;
            Adjusted.FastAux.Source = fastSource;
        end
    end

    AdjustInfo = struct();
    AdjustInfo.RunMode = RunMode;
    AdjustInfo.SourceLevel = SL;
    AdjustInfo.Sensitivity = Sensitivity;
    AdjustInfo.AmpGain = AmpGain;
    AdjustInfo.NL = NL;
    AdjustInfo.SystemGain = systemGain;
    AdjustInfo.Message = '强度调节仅基于已计算结果后处理完成，未重新计算混响传播/散射。';
end

% ========================================================================
function RLParams = buildRLParamsLocal(InputParams, AdjustParams, SL, Sensitivity, AmpGain, NL)
    RLParams = struct();
    RLParams.Sensitivity = Sensitivity;
    RLParams.AmpGain = AmpGain;
    RLParams.SourceLevel = SL;
    RLParams.NL = NL;
    RLParams.WindowSec = getFieldOrDefaultLocal(AdjustParams, 'WindowSec', 0.05);
    RLParams.CWMethod = getFieldOrDefaultLocal(AdjustParams, 'CWMethod', 'third_octave');
    RLParams.UseZeroPhaseFilter = getFieldOrDefaultLocal(AdjustParams, 'UseZeroPhaseFilter', true);
    RLParams.FilterOrder = getFieldOrDefaultLocal(AdjustParams, 'FilterOrder', 4);

    % 信号类型与频带，优先 AdjustParams，其次 InputParams。
    sigMod = getFieldOrDefaultLocal(AdjustParams, 'sigMod', getFieldOrDefaultLocal(InputParams, 'sigMod', []));
    if isempty(sigMod)
        sigType = lower(string(getFieldOrDefaultLocal(AdjustParams, 'SignalType', getFieldOrDefaultLocal(InputParams, 'SignalType', 'CW'))));
        switch sigType
            case "cw"
                sigMod = 1;
            case "hfm"
                sigMod = 2;
            otherwise
                sigMod = 1;
        end
    end
    RLParams.sigMod = sigMod;

    f0 = getFieldOrDefaultLocal(AdjustParams, 'f0', getFieldOrDefaultLocal(InputParams, 'f0', 500));
    B = getFieldOrDefaultLocal(AdjustParams, 'B', getFieldOrDefaultLocal(InputParams, 'B', 400));
    RLParams.fCW = getFieldOrDefaultLocal(AdjustParams, 'fCW', getFieldOrDefaultLocal(InputParams, 'fCW', f0));
    RLParams.fStart = getFieldOrDefaultLocal(AdjustParams, 'fStart', getFieldOrDefaultLocal(InputParams, 'fStart', max(1, f0 - B/2)));
    RLParams.fEnd = getFieldOrDefaultLocal(AdjustParams, 'fEnd', getFieldOrDefaultLocal(InputParams, 'fEnd', f0 + B/2));
    RLParams.Band = getFieldOrDefaultLocal(AdjustParams, 'Band', getFieldOrDefaultLocal(InputParams, 'Band', []));
    RLParams.TpCW = getFieldOrDefaultLocal(AdjustParams, 'TpCW', getFieldOrDefaultLocal(InputParams, 'TpCW', 0.2));
    RLParams.TpHFM = getFieldOrDefaultLocal(AdjustParams, 'TpHFM', getFieldOrDefaultLocal(InputParams, 'TpHFM', 0.2));
end

% ========================================================================
function [IRTotal, timeFast, sourceName] = getFastIRTotalLocal(ResultsBase, newSL, newNL)
    IRTotal = [];
    timeFast = [];
    sourceName = '';

    if isfield(ResultsBase, 'FastInfo') && isstruct(ResultsBase.FastInfo) && isfield(ResultsBase.FastInfo, 'IRTotal')
        IRTotal = ResultsBase.FastInfo.IRTotal(:);
        sourceName = 'FastInfo.IRTotal';
        if isfield(ResultsBase, 'timeFast') && ~isempty(ResultsBase.timeFast)
            timeFast = ResultsBase.timeFast(:);
        elseif isfield(ResultsBase.FastInfo, 'fs') && ~isempty(ResultsBase.FastInfo.fs)
            fsFast = ResultsBase.FastInfo.fs;
            timeFast = (0:numel(IRTotal)-1).' ./ fsFast;
        else
            timeFast = (0:numel(IRTotal)-1).';
        end
        return;
    end

    % 兜底：若只有旧 RLFast，则先扣除旧噪声与旧声源级，反推等效 IR。
    if isfield(ResultsBase, 'RLFast') && ~isempty(ResultsBase.RLFast)
        RLFastOld = ResultsBase.RLFast(:);
        oldSL = newSL;
        oldNL = newNL;
        if isfield(ResultsBase, 'FastInfo') && isstruct(ResultsBase.FastInfo)
            oldSL = getFieldOrDefaultLocal(ResultsBase.FastInfo, 'SourceLevel', oldSL);
            oldNL = getFieldOrDefaultLocal(ResultsBase.FastInfo, 'NL', oldNL);
        end
        oldTotalEnergy = 10.^(RLFastOld ./ 10);
        if isfinite(oldNL)
            oldNoiseEnergy = 10.^(oldNL ./ 10);
        else
            oldNoiseEnergy = 0;
        end
        oldSignalEnergy = max(oldTotalEnergy - oldNoiseEnergy, 0);
        IRTotal = oldSignalEnergy ./ max(10.^(oldSL ./ 10), realmin);
        sourceName = 'estimated_from_RLFast';
        if isfield(ResultsBase, 'timeFast') && ~isempty(ResultsBase.timeFast)
            timeFast = ResultsBase.timeFast(:);
        else
            timeFast = (0:numel(IRTotal)-1).';
        end
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
