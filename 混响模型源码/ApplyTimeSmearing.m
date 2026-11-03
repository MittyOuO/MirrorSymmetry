function [yDir, ySca, timeRt, TxWave] = ApplyTimeSmearing(hSca, hDir, spreadTime, varargin)
% ApplyTimeSmearing
% Convolve the impulse responses with the configured source waveform.
%
% Supported call styles:
%   ApplyTimeSmearing(hSca, hDir, spreadTime, InputParams)
%   ApplyTimeSmearing(hSca, hDir, spreadTime, f0, B, fs, Itg)
%
% The second style is kept for legacy callers. New callers should pass the
% full InputParams structure so combined signals such as HFM+CW and CW+HFM
% can preserve their signal order, HFM sweep type, and separate frequency
% bands.

InputParams = parseApplyInputsLocal(varargin{:});

fs = getFieldOrDefaultLocal(InputParams, {'fs','Fs','fsSig'}, []);
if isempty(fs) || ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('ApplyTimeSmearing:InvalidFs', 'InputParams.fs 必须为大于 0 的采样频率。');
end
fs = double(fs);

SigInput = buildSignalInputLocal(InputParams, fs);
[txWaveVec, txTime, SigMeta] = GenerateTxSignal(SigInput);
txWaveVec = txWaveVec(:);

if isempty(txWaveVec) || all(txWaveVec == 0)
    error('ApplyTimeSmearing:EmptyTxSignal', '生成的发射信号为空或全零，无法进行卷积。');
end

% Optional Doppler time scaling for the source waveform.
dopplerEnable = logical(getFieldOrDefaultLocal(InputParams, {'DopplerEnable','EnableDoppler'}, true));
platformSpeedKn = getFieldOrDefaultLocal(InputParams, {'PlatformSpeedKn','PlatformSpeed','SpeedKn'}, 0);
dopplerCosine = getFieldOrDefaultLocal(InputParams, {'DopplerCosine','RadialVelocityCosine'}, 1);
c0 = getFieldOrDefaultLocal(InputParams, {'SoundSpeed','c','c0'}, 1500);
dopplerMode = lower(string(getFieldOrDefaultLocal(InputParams, {'DopplerMode'}, 'two_way')));

vPlatform = double(platformSpeedKn) * 0.514444; % knot -> m/s
if ~isfinite(vPlatform)
    vPlatform = 0;
end
if ~isfinite(c0) || c0 <= 0
    c0 = 1500;
end

switch dopplerMode
    case "one_way"
        muSum = double(dopplerCosine);
    case "bistatic"
        muIn = getFieldOrDefaultLocal(InputParams, {'DopplerInCosine'}, double(dopplerCosine));
        muOut = getFieldOrDefaultLocal(InputParams, {'DopplerOutCosine'}, double(dopplerCosine));
        muSum = double(muIn) + double(muOut);
    otherwise
        muSum = 2 * double(dopplerCosine);
end

if dopplerEnable && abs(vPlatform) > 0
    dopplerScale = 1 + (vPlatform / c0) * muSum;
    dopplerScale = max(0.95, min(1.05, dopplerScale));
    txWaveVec = applyTimeScaleLocal(txWaveVec, dopplerScale);
    txTime = (0:numel(txWaveVec)-1).' / fs;
else
    dopplerScale = 1;
end

hSca = hSca(:);
hDir = hDir(:);

spreadPoints = round(double(spreadTime) / 1000 * fs);
if spreadPoints > 1
    tKernel = linspace(-2, 2, spreadPoints).';
    kernel = exp(-tKernel.^2);
    kernel = kernel ./ sum(kernel);
    hDirUse = conv(hDir, kernel, 'same');
else
    hDirUse = hDir;
end

ySca = conv(hSca, txWaveVec, 'full');
yDir = conv(hDirUse, txWaveVec, 'full');

totalLength = max(numel(ySca), numel(yDir));
ySca = padToLengthLocal(ySca, totalLength);
yDir = padToLengthLocal(yDir, totalLength);
timeRt = (0:totalLength-1).' / fs;

TxWave = struct();
TxWave.st = txWaveVec;
TxWave.t = txTime(:);
TxWave.fs = fs;
TxWave.SigInput = SigInput;
TxWave.SigMeta = SigMeta;
TxWave.SourceLevel = getFieldOrDefaultLocal(InputParams, {'SourceLevel','SL'}, []);
TxWave.spreadTime = spreadTime;
TxWave.DopplerScale = dopplerScale;
TxWave.DopplerMode = dopplerMode;
TxWave.PlatformSpeedKn = platformSpeedKn;
end

function InputParams = parseApplyInputsLocal(varargin)
    if numel(varargin) == 1 && isstruct(varargin{1})
        InputParams = varargin{1};
        return;
    end

    if numel(varargin) == 4
        f0 = varargin{1};
        B = varargin{2};
        fs = varargin{3};
        Itg = varargin{4};

        InputParams = struct();
        InputParams.f0 = double(f0);
        InputParams.fCW = double(f0);
        InputParams.B = double(B);
        InputParams.fs = double(fs);
        InputParams.fsSig = double(fs);
        InputParams.Itg = double(Itg);
        InputParams.TpCW = max(eps, double(Itg));
        InputParams.TpHFM = max(eps, double(Itg));

        if isfinite(double(B)) && double(B) > 0
            InputParams.sigType = 'HFM';
            InputParams.sigMod = 2;
            InputParams.fStart = double(f0) - double(B) / 2;
            InputParams.fEnd = double(f0) + double(B) / 2;
            InputParams.HFMType = '升频';
        else
            InputParams.sigType = 'CW';
            InputParams.sigMod = 1;
        end
        return;
    end

    error('ApplyTimeSmearing:InvalidInput', ...
        'ApplyTimeSmearing 需要 InputParams，或旧版 f0/B/fs/Itg 四个参数。');
end

function SigInput = buildSignalInputLocal(InputParams, fs)
    if isfield(InputParams, 'TxSigInput') && isstruct(InputParams.TxSigInput) && ~isempty(InputParams.TxSigInput)
        SigInput = InputParams.TxSigInput;
    else
        SigInput = struct();
    end

    copyNames = {'sigType','SignalType','sigMod','f0','F0','fCW','TpCW', ...
        'fStart','fEnd','TpHFM','TpLFM','Tp','B','HFMType','hfmType', ...
        'SweepType','sweepType','customPath','customSignal','customTime', ...
        'customFs','ImportedTxSignal','ImportedTxTime','ImportedTxFs', ...
        'normalizeMode','SourceLevel','SL'};

    for ii = 1:numel(copyNames)
        fn = copyNames{ii};
        if isfield(InputParams, fn) && ~isempty(InputParams.(fn))
            SigInput.(fn) = InputParams.(fn);
        end
    end

    SigInput.fsSig = fs;

    if ~isfield(SigInput, 'normalizeMode') || isempty(SigInput.normalizeMode)
        SigInput.normalizeMode = 'peak';
    end

    if (~isfield(SigInput, 'fCW') || isempty(SigInput.fCW)) && isfield(SigInput, 'f0') && ~isempty(SigInput.f0)
        SigInput.fCW = SigInput.f0;
    end
    if (~isfield(SigInput, 'fCW') || isempty(SigInput.fCW)) && isfield(SigInput, 'F0') && ~isempty(SigInput.F0)
        SigInput.fCW = SigInput.F0;
    end

    if ~hasFieldValueLocal(SigInput, 'sigType') && ~hasFieldValueLocal(SigInput, 'sigMod')
        SigInput = inferLegacySignalTypeLocal(SigInput);
    end

    if requiresHFMFieldsLocal(SigInput)
        SigInput = fillLegacyHFMFieldsLocal(SigInput);
    end

    if requiresCWFieldsLocal(SigInput)
        if (~isfield(SigInput, 'TpCW') || isempty(SigInput.TpCW)) && isfield(InputParams, 'Itg') && ~isempty(InputParams.Itg)
            SigInput.TpCW = InputParams.Itg;
        end
        if (~isfield(SigInput, 'fCW') || isempty(SigInput.fCW)) && isfield(InputParams, 'f0') && ~isempty(InputParams.f0)
            SigInput.fCW = InputParams.f0;
        end
    end

    if requiresHFMFieldsLocal(SigInput)
        if (~isfield(SigInput, 'TpHFM') || isempty(SigInput.TpHFM)) && isfield(InputParams, 'Itg') && ~isempty(InputParams.Itg)
            SigInput.TpHFM = InputParams.Itg;
        end
        if ~isfield(SigInput, 'HFMType') || isempty(SigInput.HFMType)
            SigInput.HFMType = getFieldOrDefaultLocal(InputParams, {'HFMType','hfmType','SweepType','sweepType'}, '升频');
        end
    end
end

function SigInput = inferLegacySignalTypeLocal(SigInput)
    hasHFM = hasFieldValueLocal(SigInput, 'TpHFM') || ...
        (hasFieldValueLocal(SigInput, 'fStart') && hasFieldValueLocal(SigInput, 'fEnd')) || ...
        (hasFieldValueLocal(SigInput, 'B') && double(SigInput.B) > 0);
    hasCW = hasFieldValueLocal(SigInput, 'fCW') || hasFieldValueLocal(SigInput, 'f0') || hasFieldValueLocal(SigInput, 'F0');

    if hasHFM && hasCW && hasFieldValueLocal(SigInput, 'TpCW')
        SigInput.sigType = 'HFM_CW';
        SigInput.sigMod = 3;
    elseif hasHFM
        SigInput.sigType = 'HFM';
        SigInput.sigMod = 2;
    else
        SigInput.sigType = 'CW';
        SigInput.sigMod = 1;
    end
end

function SigInput = fillLegacyHFMFieldsLocal(SigInput)
    if hasFieldValueLocal(SigInput, 'fStart') && hasFieldValueLocal(SigInput, 'fEnd')
        return;
    end

    f0 = getFieldOrDefaultLocal(SigInput, {'f0','F0','fCW'}, []);
    B = getFieldOrDefaultLocal(SigInput, {'B','Bandwidth'}, []);
    if isempty(f0) || isempty(B) || ~isfinite(double(f0)) || ~isfinite(double(B)) || double(B) <= 0
        return;
    end

    SigInput.fStart = double(f0) - double(B) / 2;
    SigInput.fEnd = double(f0) + double(B) / 2;
end

function tf = requiresHFMFieldsLocal(S)
    [hasType, s] = readSigTypeStringLocal(S);
    if hasType
        tf = contains(s, 'HFM');
    elseif hasFieldValueLocal(S, 'sigMod')
        tf = ismember(double(S.sigMod), [2 3 4]);
    else
        tf = false;
    end
end

function tf = requiresCWFieldsLocal(S)
    [hasType, s] = readSigTypeStringLocal(S);
    if hasType
        tf = contains(s, 'CW') && ~contains(s, 'CUSTOM');
    elseif hasFieldValueLocal(S, 'sigMod')
        tf = ismember(double(S.sigMod), [1 3 4]);
    else
        tf = false;
    end
end

function [tf, s] = readSigTypeStringLocal(S)
    tf = false;
    s = "";
    if isfield(S, 'sigType') && ~isempty(S.sigType)
        s = upper(strtrim(string(S.sigType)));
        s = strrep(s, '+', '_');
        s = strrep(s, '-', '_');
        s = strrep(s, ' ', '');
        tf = true;
    elseif isfield(S, 'SignalType') && ~isempty(S.SignalType)
        s = upper(strtrim(string(S.SignalType)));
        s = strrep(s, '+', '_');
        s = strrep(s, '-', '_');
        s = strrep(s, ' ', '');
        tf = true;
    end
end

function tf = hasFieldValueLocal(S, fieldName)
    tf = isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName));
end

function y = padToLengthLocal(y, n)
    y = y(:);
    if numel(y) < n
        y = [y; zeros(n - numel(y), 1)];
    end
end

function val = getFieldOrDefaultLocal(S, fieldName, defaultVal)
    val = defaultVal;

    if ~isstruct(S)
        return;
    end

    if ischar(fieldName) || isstring(fieldName)
        fieldList = cellstr(fieldName);
    elseif iscell(fieldName)
        fieldList = fieldName;
    else
        return;
    end

    for ii = 1:numel(fieldList)
        fn = fieldList{ii};
        if isfield(S, fn) && ~isempty(S.(fn))
            val = S.(fn);
            return;
        end
    end
end

function yScaled = applyTimeScaleLocal(x, scale)
    x = x(:);

    if isempty(x)
        yScaled = x;
        return;
    end

    if ~isfinite(scale) || scale <= 0
        scale = 1;
    end

    nOld = numel(x);
    nNew = max(1, round(nOld / scale));

    tOld = (0:nOld-1).';
    tNew = (0:nNew-1).' * scale;

    yScaled = interp1(tOld, x, tNew, 'linear', 0);
    yScaled = yScaled(:);
end
