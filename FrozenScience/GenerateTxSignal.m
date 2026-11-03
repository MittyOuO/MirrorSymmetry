function [st, t, SigMeta, SigComponents] = GenerateTxSignal(SigInput)
% GenerateTxSignal

% 支持信号类型：
%   CW        : 单频连续波脉冲
%   LFM       : 线性调频脉冲
%   HFM       : 双曲调频脉冲
%   CW_HFM    : 先 CW 后 HFM，也兼容 'CW+HFM'
%   HFM_CW    : 先 HFM 后 CW，也兼容 'HFM+CW'
%   custom    : 导入本地信号或直接使用已传入信号
%
% 推荐输入字段：
%   SigInput.sigType      : 'CW'/'HFM'/'CW_HFM'/'HFM_CW'/'custom'
%   SigInput.sigMod       : 1=CW, 2=HFM, 3=HFM_CW, 4=CW_HFM, 5=custom
%
%   SigInput.fsSig        : 发射信号采样频率，Hz
%   SigInput.SourceLevel  : 声源级，dB；本函数只保存，不用于幅值换算
%
%   SigInput.fCW          : CW 单频信号频率，Hz
%   SigInput.TpCW         : CW 脉冲长度，s
%
%   SigInput.HFMType      : HFM 调频形式，'升频'/'降频'（兼容 'up'/'down'）
%   SigInput.fStart       : HFM 频带下限频率，Hz
%   SigInput.fEnd         : HFM 频带上限频率，Hz
%   SigInput.TpHFM        : HFM 脉冲长度，s
%
%   SigInput.customSignal : custom 时可直接传入的一维信号
%   SigInput.customTime   : custom 时可选时间轴
%   SigInput.customFs     : custom 时可选采样频率
%   SigInput.customPath   : custom 时可选 .mat 或 .bin 文件路径
%
% custom 文件约定：
%   .mat：优先读取 signal / st / TxSignal / sigData 中任意一个变量；
%         若存在 Time / t / time，则读取为时间轴；
%         若存在 fsSig / Fs / fs，则读取为采样频率。
%   .bin：第一版约定为 double 类型的一维数组；
%         采样频率使用 SigInput.fsSig。
%
% 输出：
%   st      : 发射信号列向量，默认峰值归一化
%   t       : 时间轴列向量，单位 s
%   SigMeta : 信号参数记录结构体
%
% 注意：
%   SourceLevel 不在本函数中转换幅值。st 默认作为归一化发射波形，
%   物理量级由后续模型计算或实测比对中的 SourceLevel / Sensitivity /
%   AmpGain 等系统参数完成。

    if ~isstruct(SigInput)
        error('SigInput 必须为结构体。');
    end

    sigType = parseSigType(SigInput);

    fsSig = getFieldLocal(SigInput, 'fsSig', []);
    if isempty(fsSig) || ~isnumeric(fsSig) || ~isscalar(fsSig) || ~isfinite(fsSig) || fsSig <= 0
        error('SigInput.fsSig 必须为大于 0 的采样频率。');
    end
    fsSig = double(fsSig);

    SigComponents = repmat(emptyComponentLocal(), 0, 1);

    switch sigType
        case 'CW'
            fCW = getPositiveScalar(SigInput, 'fCW');
            TpCW = getPositiveScalar(SigInput, 'TpCW');
            validateNyquist(fCW, fsSig, 'CW 频率');
            [st, t] = makeCW(fCW, TpCW, fsSig);
            SigComponents = makeComponentLocal('CW', st, t, 0, fsSig, fCW);

        case 'LFM'
            [fStart, fEnd, TpLFM] = getLFMParams(SigInput);
            validateLFMFreq(fStart, fEnd, fsSig);
            [st, t] = makeLFM(fStart, fEnd, TpLFM, fsSig);
            SigComponents = makeComponentLocal('LFM', st, t, 0, fsSig, mean([fStart fEnd]));


        case 'HFM'
            [fStart, fEnd, sweepStart, sweepEnd, HFMType] = getHFMParams(SigInput, fsSig);
            TpHFM = getPositiveScalar(SigInput, 'TpHFM');
            [st, t] = makeHFM(sweepStart, sweepEnd, TpHFM, fsSig, HFMType);
            SigComponents = makeComponentLocal('HFM', st, t, 0, fsSig, mean([fStart fEnd]));

        case 'CW_HFM'
            fCW = getPositiveScalar(SigInput, 'fCW');
            TpCW = getPositiveScalar(SigInput, 'TpCW');
            [fStart, fEnd, sweepStart, sweepEnd, HFMType] = getHFMParams(SigInput, fsSig);
            TpHFM = getPositiveScalar(SigInput, 'TpHFM');
            validateNyquist(fCW, fsSig, 'CW 频率');
            [s1, t1] = makeCW(fCW, TpCW, fsSig);
            [s2, t2] = makeHFM(sweepStart, sweepEnd, TpHFM, fsSig, HFMType);
            [st, t] = concatSignals({s1, s2}, fsSig);
            SigComponents(1,1) = makeComponentLocal('CW', s1, t1, 0, fsSig, fCW);
            SigComponents(2,1) = makeComponentLocal('HFM', s2, t2, numel(s1)/fsSig, fsSig, mean([fStart fEnd]));

        case 'HFM_CW'
            [fStart, fEnd, sweepStart, sweepEnd, HFMType] = getHFMParams(SigInput, fsSig);
            TpHFM = getPositiveScalar(SigInput, 'TpHFM');
            fCW = getPositiveScalar(SigInput, 'fCW');
            TpCW = getPositiveScalar(SigInput, 'TpCW');
            validateNyquist(fCW, fsSig, 'CW 频率');
            [s1, t1] = makeHFM(sweepStart, sweepEnd, TpHFM, fsSig, HFMType);
            [s2, t2] = makeCW(fCW, TpCW, fsSig);
            [st, t] = concatSignals({s1, s2}, fsSig);
            SigComponents(1,1) = makeComponentLocal('HFM', s1, t1, 0, fsSig, mean([fStart fEnd]));
            SigComponents(2,1) = makeComponentLocal('CW', s2, t2, numel(s1)/fsSig, fsSig, fCW);

        case 'custom'
            [st, t, fsCustom, customInfo] = makeCustomSignal(SigInput, fsSig);
            fsSig = fsCustom;
            SigComponents = makeComponentLocal('custom', st, t, 0, fsSig, NaN);

        otherwise
            error('未知信号类型：%s', sigType);
    end

    st = double(st(:));
    t = double(t(:));

    if isempty(st) || isempty(t)
        error('生成的发射信号为空。');
    end
    if numel(st) ~= numel(t)
        error('生成的发射信号与时间轴长度不一致。');
    end

    normalizationScale = 1;
    normalizeMode = lower(string(getFieldLocal(SigInput, 'normalizeMode', 'peak')));
    switch normalizeMode
        case 'peak'
            mx = max(abs(st));
            if mx > 0
                normalizationScale = 1 / mx;
                st = st * normalizationScale;
            end
        case 'energy'
            e = sqrt(sum(abs(st).^2));
            if e > 0
                normalizationScale = 1 / e;
                st = st * normalizationScale;
            end
        case {'none','no'}
            % 不归一化
        otherwise
            error('normalizeMode 只能为 peak / energy / none。');
    end

    for kk = 1:numel(SigComponents)
        SigComponents(kk).Waveform = SigComponents(kk).Waveform * normalizationScale;
    end

    SigMeta = struct();
    SigMeta.sigType = sigType;
    SigMeta.sigMod = sigTypeToMod(sigType);
    SigMeta.fsSig = fsSig;
    SigMeta.Duration = numel(st) / fsSig;
    SigMeta.NumSamples = numel(st);
    SigMeta.NormalizeMode = char(normalizeMode);

    if isfield(SigInput, 'SourceLevel') && ~isempty(SigInput.SourceLevel)
        SigMeta.SourceLevel = SigInput.SourceLevel;
    else
        SigMeta.SourceLevel = [];
    end

    fieldsToCopy = {'fCW','TpCW','fStart','fEnd','TpLFM','TpHFM','B','HFMType','hfmType','customPath'};
    for k = 1:numel(fieldsToCopy)
        fn = fieldsToCopy{k};
        if isfield(SigInput, fn)
            SigMeta.(fn) = SigInput.(fn);
        end
    end

    if exist('HFMType', 'var')
        SigMeta.HFMType = HFMType;
        SigMeta.HFMSweepStart = sweepStart;
        SigMeta.HFMSweepEnd = sweepEnd;
        SigMeta.fStart = fStart;
        SigMeta.fEnd = fEnd;
    end

    if strcmp(sigType, 'custom') && exist('customInfo', 'var')
        SigMeta.CustomInfo = customInfo;
    end
end

function component = emptyComponentLocal()
component = struct('Type', '', 'Waveform', [], 'Time', [], ...
    'StartTime', 0, 'StartSample', 1, 'Duration', 0, ...
    'ReferenceFrequency', NaN);
end

function component = makeComponentLocal(typeName, waveform, time, startTime, fs, referenceFrequency)
component = emptyComponentLocal();
component.Type = char(typeName);
component.Waveform = double(waveform(:));
component.Time = double(time(:));
component.StartTime = double(startTime);
component.StartSample = round(component.StartTime * fs) + 1;
component.Duration = numel(component.Waveform) / fs;
component.ReferenceFrequency = double(referenceFrequency);
end

% ======================= helper functions =======================
function sigType = parseSigType(P)
    if isfield(P, 'sigType') && ~isempty(P.sigType)
        s = upper(strtrim(string(P.sigType)));
        s = strrep(s, '-', '_');
        s = strrep(s, '+', '_');
        s = strrep(s, ' ', '');

        switch s
            case 'CW'
                sigType = 'CW';
            case {'LFM'}
                sigType = 'LFM';
            case 'HFM'
                sigType = 'HFM';
            case {'CW_HFM','CWHFM'}
                sigType = 'CW_HFM';
            case {'HFM_CW','HFMCW'}
                sigType = 'HFM_CW';
            case {'CUSTOM','导入本地信号','自定义'}
                sigType = 'custom';
            otherwise
                error('无法识别 sigType：%s', string(P.sigType));
        end
        return;
    end

    if isfield(P, 'sigMod') && ~isempty(P.sigMod)
        switch double(P.sigMod)
            case 1
                sigType = 'CW';
            case 2
                sigType = 'HFM';
            case 3
                sigType = 'HFM_CW';
            case 4
                sigType = 'CW_HFM';
            case 5
                sigType = 'custom';
            case 6
                sigType = 'LFM';
            otherwise
                error('sigMod 必须为 1/2/3/4/5/6。');
        end
        return;
    end
    % 兼容旧版：如果未显式提供 sigType/sigMod，则根据字段自动推断
if isfield(P, 'TpLFM') || ...
   (isfield(P, 'fStart') && isfield(P, 'fEnd') && isfield(P, 'Tp') && ...
    ~(isfield(P, 'TpHFM') && ~isempty(P.TpHFM)))
    sigType = 'LFM';
    return;
end

if isfield(P, 'TpHFM') && ~isempty(P.TpHFM)
    sigType = 'HFM';
    return;
end

if isfield(P, 'fCW') || isfield(P, 'F0') || isfield(P, 'f0')
    sigType = 'CW';
    return;
end

error('必须提供 SigInput.sigType 或 SigInput.sigMod。');
end

function sigMod = sigTypeToMod(sigType)
    switch sigType
        case 'CW'
            sigMod = 1;
        case 'LFM'
            sigMod = 6;
        case 'HFM'
            sigMod = 2;
        case 'HFM_CW'
            sigMod = 3;
        case 'CW_HFM'
            sigMod = 4;
        case 'custom'
            sigMod = 5;
        otherwise
            sigMod = NaN;
    end
end
function validateLFMFreq(fStart, fEnd, fs)
    if max(fStart, fEnd) >= fs/2
        error('LFM 的最高频率必须小于采样频率的一半。');
    end
end
function [fLow, fHigh, sweepStart, sweepEnd, HFMType] = getHFMParams(P, fs)
    fA = getPositiveScalar(P, 'fStart');
    fB = getPositiveScalar(P, 'fEnd');
    validateHFMFreq(fA, fB, fs);

    fLow = min(fA, fB);
    fHigh = max(fA, fB);
    [hasType, HFMType] = readHFMType(P);

    if hasType
        if strcmp(HFMType, '升频')
            sweepStart = fLow;
            sweepEnd = fHigh;
        else
            sweepStart = fHigh;
            sweepEnd = fLow;
        end
    else
        sweepStart = fA;
        sweepEnd = fB;
        if fB >= fA
            HFMType = '升频';
        else
            HFMType = '降频';
        end
    end
end

function [hasType, HFMType] = readHFMType(P)
    hasType = false;
    HFMType = '升频';
    names = {'HFMType','hfmType','SweepType','sweepType'};
    raw = [];
    for k = 1:numel(names)
        fn = names{k};
        if isfield(P, fn) && ~isempty(P.(fn))
            raw = P.(fn);
            hasType = true;
            break;
        end
    end
    if ~hasType
        return;
    end

    s = lower(strtrim(string(raw)));
    if any(s == ["升频","up","upward","upsweep","increase","increasing","正扫","上扫"])
        HFMType = '升频';
    elseif any(s == ["降频","down","downward","downsweep","decrease","decreasing","反扫","下扫"])
        HFMType = '降频';
    else
        error('HFM 调频形式必须为升频或降频。');
    end
end

function [s, t] = makeCW(fCW, T, fs)
    N = max(1, round(T * fs));
    t = (0:N-1).' / fs;
    if abs(fCW - fs/2) <= max(eps(fs), 1e-9 * fs)
        s = cos(2*pi*fCW*t);
    else
        s = sin(2*pi*fCW*t);
    end
end
function [fStart, fEnd, TpLFM] = getLFMParams(P)
    % LFM 推荐直接使用 fStart/fEnd/TpLFM。
    % 若只给 fCenter 与 B，则自动换算上下限频率。
    if isfield(P, 'fStart') && ~isempty(P.fStart) && isfield(P, 'fEnd') && ~isempty(P.fEnd)
        fStart = getPositiveScalar(P, 'fStart');
        fEnd = getPositiveScalar(P, 'fEnd');
    elseif isfield(P, 'fCenter') && ~isempty(P.fCenter) && isfield(P, 'B') && ~isempty(P.B)
        fCenter = getPositiveScalar(P, 'fCenter');
        B = getPositiveScalar(P, 'B');
        fStart = fCenter - B/2;
        fEnd = fCenter + B/2;
        if fStart <= 0
            error('由 fCenter 和 B 推得的 LFM 起始频率必须为正数。');
        end
    else
        error('LFM 必须提供 SigInput.fStart/fEnd，或提供 SigInput.fCenter 与 SigInput.B。');
    end

    if isfield(P, 'TpLFM') && ~isempty(P.TpLFM)
        TpLFM = getPositiveScalar(P, 'TpLFM');
    elseif isfield(P, 'Tp') && ~isempty(P.Tp)
        TpLFM = getPositiveScalar(P, 'Tp');
    else
        error('LFM 必须提供 SigInput.TpLFM 或 SigInput.Tp。');
    end
end

function [s, t] = makeLFM(fStart, fEnd, T, fs)
    N = max(1, round(T * fs));
    t = (0:N-1).' / fs;
    if abs(fEnd - fStart) < eps
        s = sin(2*pi*fStart*t);
        return;
    end
    k = (fEnd - fStart) / T;              % Hz/s
    phaseCycles = fStart*t + 0.5*k*t.^2; % cycles
    s = sin(2*pi*phaseCycles);
end

function [s, t] = makeHFM(fStart, fEnd, T, fs, HFMType)
    if nargin < 5 || isempty(HFMType)
        if fEnd >= fStart
            HFMType = '升频';
        else
            HFMType = '降频';
        end
    end

    N = max(1, round(T * fs));
    t = (0:N-1).' / fs;

    if abs(fStart - fEnd) < eps
        s = sin(2*pi*fStart*t);
        return;
    end

    % HFM 近似：f(t)= fStart*fEnd*T / (fEnd*T + (fStart-fEnd)*t)
    % 通过积分瞬时频率得到相位。
    a = fStart - fEnd;
    b = fEnd * T;
    denom = b + a*t;
    if any(denom <= 0)
        error('HFM 参数导致相位公式分母非正，请检查 fStart/fEnd/TpHFM。');
    end
    phaseCycles = (fStart*fEnd*T/a) .* log(denom ./ b);
    instFreq = (fStart*fEnd*T) ./ denom;
    amp = makeHFMTiltEnvelope(instFreq, HFMType);
    s = amp .* sin(2*pi*phaseCycles);
end

function amp = makeHFMTiltEnvelope(instFreq, HFMType)
    instFreq = double(instFreq(:));
    fLow = min(instFreq);
    fHigh = max(instFreq);

    if ~isfinite(fLow) || ~isfinite(fHigh) || fHigh <= fLow
        amp = ones(size(instFreq));
        return;
    end

    switch char(HFMType)
        case '升频'
            amp = (instFreq ./ fHigh).^2;
        case '降频'
            amp = (fLow ./ instFreq);
        otherwise
            amp = ones(size(instFreq));
    end

    amp = amp ./ max(abs(amp));
end

function [s, t] = concatSignals(signalCells, fs)
    s = [];
    for k = 1:numel(signalCells)
        s = [s; signalCells{k}(:)]; %#ok<AGROW>
    end
    t = (0:numel(s)-1).' / fs;
end

function [s, t, fsOut, info] = makeCustomSignal(P, fsTarget)
    info = struct();

    % 优先使用直接传入的一维信号。
    if isfield(P, 'customSignal') && ~isempty(P.customSignal)
        s = double(P.customSignal(:));
        info.Source = 'customSignal';

        if isfield(P, 'customTime') && ~isempty(P.customTime)
            tRaw = double(P.customTime(:));
        else
            tRaw = [];
        end

        if isfield(P, 'customFs') && ~isempty(P.customFs)
            fsRaw = double(P.customFs(1));
        else
            fsRaw = [];
        end

        [s, t, fsOut, info] = finalizeCustomSignal(s, tRaw, fsRaw, fsTarget, info);
        return;
    end

    customPath = getFieldLocal(P, 'customPath', '');
    if isempty(customPath) || ~(isfile(customPath))
        error('custom 信号需要提供 SigInput.customSignal 或有效的 SigInput.customPath。');
    end

    [~, ~, ext] = fileparts(customPath);
    ext = lower(ext);
    info.Source = customPath;

    switch ext
        case '.mat'
            raw = load(customPath);
            [s, sigName] = readFirstNumericVector(raw, {'signal','st','TxSignal','sigData'});
            info.SignalVariable = sigName;

            [tRaw, timeName] = readOptionalNumericVector(raw, {'Time','t','time'});
            info.TimeVariable = timeName;

            [fsRaw, fsName] = readOptionalScalar(raw, {'fsSig','Fs','fs'});
            info.FsVariable = fsName;

        case '.bin'
            fid = fopen(customPath, 'rb');
            if fid < 0
                error('无法打开 .bin 文件：%s', customPath);
            end
            cleaner = onCleanup(@() fclose(fid));
            s = fread(fid, inf, 'double');
            if isempty(s)
                error('.bin 文件为空，或不是 double 类型连续数据。');
            end
            tRaw = [];
            fsRaw = fsTarget;
            info.SignalVariable = 'binary-double';
            info.TimeVariable = '';
            info.FsVariable = 'SigInput.fsSig';

        otherwise
            error('customPath 仅支持 .mat 或 .bin 文件。');
    end

    [s, t, fsOut, info] = finalizeCustomSignal(s, tRaw, fsRaw, fsTarget, info);
end

function [s, t, fsOut, info] = finalizeCustomSignal(s, tRaw, fsRaw, fsTarget, info)
    s = double(s(:));

    if isempty(s)
        error('custom 信号为空。');
    end

    if ~isempty(tRaw)
        tRaw = double(tRaw(:));
        if numel(tRaw) ~= numel(s)
            error('custom 信号与时间轴长度不一致。');
        end
        dt = median(diff(tRaw));
        if isempty(dt) || ~isfinite(dt) || dt <= 0
            error('custom 时间轴无效，无法计算采样率。');
        end
        fsRawFromTime = 1 / dt;
        if isempty(fsRaw) || ~isfinite(fsRaw) || fsRaw <= 0
            fsRaw = fsRawFromTime;
        end
    end

    if isempty(fsRaw) || ~isfinite(fsRaw) || fsRaw <= 0
        fsRaw = fsTarget;
    end

    if abs(fsRaw - fsTarget) / fsTarget > 1e-8
        s = resampleToFsLocal(s, fsRaw, fsTarget);
        fsOut = fsTarget;
    else
        fsOut = fsRaw;
    end

    t = (0:numel(s)-1).' / fsOut;
    info.fsRaw = fsRaw;
    info.fsOut = fsOut;
end

function [vec, usedName] = readFirstNumericVector(raw, names)
    vec = [];
    usedName = '';
    for k = 1:numel(names)
        name = names{k};
        if isfield(raw, name) && isnumeric(raw.(name)) && isvector(raw.(name))
            tmp = raw.(name);
            vec = tmp(:);
            usedName = name;
            return;
        end
    end

    % 兜底：寻找第一个数值向量，但跳过明显不是信号的短标量。
    fns = fieldnames(raw);
    for k = 1:numel(fns)
        candidate = raw.(fns{k});
        if isnumeric(candidate) && isvector(candidate) && numel(candidate) > 1
            vec = candidate(:);
            usedName = fns{k};
            return;
        end
    end

    error('.mat 文件中未找到 signal / st / TxSignal / sigData 或其他一维数值信号。');
end

function [vec, usedName] = readOptionalNumericVector(raw, names)
    vec = [];
    usedName = '';
    for k = 1:numel(names)
        name = names{k};
        if isfield(raw, name) && isnumeric(raw.(name)) && isvector(raw.(name))
            tmp = raw.(name);
            vec = tmp(:);
            usedName = name;
            return;
        end
    end
end

function [val, usedName] = readOptionalScalar(raw, names)
    val = [];
    usedName = '';
    for k = 1:numel(names)
        name = names{k};
        if isfield(raw, name) && isnumeric(raw.(name)) && ~isempty(raw.(name))
            tmp = raw.(name);
            val = double(tmp(1));
            usedName = name;
            return;
        end
    end
end

function y = resampleToFsLocal(x, fsRaw, fsTarget)
    x = double(x(:));
    if exist('resample', 'file') == 2
        [p, q] = rat(fsTarget / fsRaw, 1e-10);
        y = resample(x, p, q);
    else
        tRaw = (0:numel(x)-1).' / fsRaw;
        tNew = (0:1/fsTarget:tRaw(end)).';
        y = interp1(tRaw, x, tNew, 'linear', 'extrap');
    end
end

function val = getFieldLocal(s, name, defaultVal)
    if isfield(s, name) && ~isempty(s.(name))
        val = s.(name);
    else
        val = defaultVal;
    end
end

function val = getPositiveScalar(s, name)
    val = getFieldLocal(s, name, []);
    if isempty(val) || ~isnumeric(val) || ~isscalar(val) || ~isfinite(val) || val <= 0
        error('SigInput.%s 必须为正数标量。', name);
    end
    val = double(val);
end

function validateNyquist(f, fs, name)
    if f > fs/2
        error('%s 不得大于采样频率的一半。', name);
    end
end

function validateHFMFreq(fStart, fEnd, fs)
    if ~isfinite(fStart) || ~isfinite(fEnd) || fStart <= 0 || fEnd <= 0
        error('HFM 频带上下限必须为正数。');
    end
    if abs(fEnd - fStart) < eps
        error('HFM 频带上下限不能相同。');
    end
    if max(fStart, fEnd) >= fs/2
        error('HFM 的最高频率必须小于采样频率的一半。');
    end
end
