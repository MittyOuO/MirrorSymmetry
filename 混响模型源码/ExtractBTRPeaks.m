function [PeakTable, PeakInfo] = ExtractBTRPeaks(BTR, timeAxis, scanAngles, PeakParams)
% ExtractBTRPeaks  Extract visible peaks from a beam-time response (BTR).
%
%   [PeakTable, PeakInfo] = ExtractBTRPeaks(BTR, timeAxis, scanAngles, PeakParams)
%
% Purpose
%   Extract per-beam visible peaks from a BTR matrix for validation of
%   beam-time peak arrival-time error. This function is designed for the
%   formal metric chain, so it should normally be applied to the globally
%   normalized BTR, not a column-normalized display matrix.
%
% Inputs
%   BTR          : nBeam x nTime matrix. Default unit is dB relative to max.
%   timeAxis     : 1 x nTime time vector in seconds.
%   scanAngles   : nBeam x 1 or 1 x nBeam beam-angle vector in degrees.
%   PeakParams   : optional struct fields
%       InputScale              'dB' (default) or 'linearPower'
%       SmoothTime              temporal moving-average window, seconds (default 0.05)
%       Pfa                     CFAR false-alarm probability (default 1e-4)
%       ThresholdMode           'hybrid' (default), 'relative', or 'cfar'
%       RelativeThresholdDB     global visibility floor in dB (default -35)
%       CFARTrainingTime        training window per side, seconds (default 1.0)
%       CFARGuardTime           guard window per side, seconds (default 0.25)
%       NoisePercentile         fallback local-noise percentile (default 50)
%       MinPeakProminenceDB     min peak / local noise ratio, dB (default 6)
%       MinPeakDistanceSec      minimum spacing between peaks in one beam (default 0.6)
%       MaxNumPeaksPerBeam      maximum retained peaks per beam (default Inf)
%       BeamAnglesToUse         optional subset of scan angles
%       BeamAngleTolerance      tolerance for BeamAnglesToUse, deg (default 1e-6)
%       TimeLimits              optional [tmin tmax]
%       Verbose                 true/false (default false)
%
% Outputs
%   PeakTable columns:
%       BeamIndex, ScanAngle, PeakIndex, PeakTime, PeakValueDB,
%       PeakValueLinear, LocalNoiseDB, ProminenceDB, PeakIntervalPrev,
%       PeakIntervalNext, ThresholdDB
%
%   PeakInfo fields contain parameter values and per-beam summary.

if nargin < 4 || isempty(PeakParams)
    PeakParams = struct();
end
if nargin < 3 || isempty(scanAngles)
    scanAngles = (1:size(BTR, 1)).';
end
if nargin < 2 || isempty(timeAxis)
    error('ExtractBTRPeaks:MissingTimeAxis', 'timeAxis 不能为空。');
end
if isempty(BTR) || ~ismatrix(BTR)
    error('ExtractBTRPeaks:InvalidBTR', 'BTR 必须为二维矩阵。');
end

timeAxis = double(timeAxis(:).');
scanAngles = double(scanAngles(:));
[nBeam, nTime] = size(BTR);
if numel(timeAxis) ~= nTime
    error('ExtractBTRPeaks:TimeAxisMismatch', 'numel(timeAxis) 必须等于 size(BTR,2)。');
end
if numel(scanAngles) ~= nBeam
    error('ExtractBTRPeaks:AngleMismatch', 'numel(scanAngles) 必须等于 size(BTR,1)。');
end

inputScale = lower(char(getFieldOrDefaultLocal(PeakParams, 'InputScale', 'dB')));
smoothTime = double(getFieldOrDefaultLocal(PeakParams, 'SmoothTime', 0.05));
Pfa = double(getFieldOrDefaultLocal(PeakParams, 'Pfa', 1e-4));
thresholdMode = lower(char(getFieldOrDefaultLocal(PeakParams, 'ThresholdMode', 'hybrid')));
relativeThresholdDB = double(getFieldOrDefaultLocal(PeakParams, 'RelativeThresholdDB', -35));
cfarTrainingTime = double(getFieldOrDefaultLocal(PeakParams, 'CFARTrainingTime', 1.0));
cfarGuardTime = double(getFieldOrDefaultLocal(PeakParams, 'CFARGuardTime', 0.25));
noisePercentile = double(getFieldOrDefaultLocal(PeakParams, 'NoisePercentile', 50));
minPromDB = double(getFieldOrDefaultLocal(PeakParams, 'MinPeakProminenceDB', 6));
minDistSec = double(getFieldOrDefaultLocal(PeakParams, 'MinPeakDistanceSec', 0.6));
maxPeaks = getFieldOrDefaultLocal(PeakParams, 'MaxNumPeaksPerBeam', Inf);
verbose = logical(getFieldOrDefaultLocal(PeakParams, 'Verbose', false));

if Pfa <= 0 || Pfa >= 1
    error('ExtractBTRPeaks:InvalidPfa', 'Pfa 必须在 (0,1) 内。');
end
cfarFactor = -log(Pfa);      % Rayleigh/amplitude-style visibility factor; 1e-4 -> 9.21.

% Time sampling.
if numel(timeAxis) >= 2
    dt = median(diff(timeAxis));
else
    dt = 1;
end
if ~isfinite(dt) || dt <= 0
    error('ExtractBTRPeaks:InvalidTimeAxis', 'timeAxis 必须递增。');
end
smoothPts = max(1, round(smoothTime / dt));
trainPts = max(1, round(cfarTrainingTime / dt));
guardPts = max(0, round(cfarGuardTime / dt));
minDistPts = max(1, round(minDistSec / dt));

% Convert BTR to linear power and dB representation.
switch inputScale
    case {'db','dbrelative','db_relative'}
        BTRdb = double(BTR);
        BTRlin = 10.^(BTRdb / 10);
    case {'linear','linearpower','power'}
        BTRlin = max(double(BTR), 0);
        BTRdb = 10 * log10(BTRlin + eps);
        if logical(getFieldOrDefaultLocal(PeakParams, 'NormalizeInputDB', true))
            BTRdb = BTRdb - max(BTRdb(:));
        end
    otherwise
        error('ExtractBTRPeaks:InvalidInputScale', 'InputScale 必须为 dB 或 linearPower。');
end

% Optional time limits.
timeMask = true(1, nTime);
if isfield(PeakParams, 'TimeLimits') && ~isempty(PeakParams.TimeLimits)
    tl = double(PeakParams.TimeLimits(:).');
    if numel(tl) ~= 2 || tl(2) <= tl(1)
        error('ExtractBTRPeaks:InvalidTimeLimits', 'TimeLimits 必须为 [tmin tmax]。');
    end
    timeMask = timeAxis >= tl(1) & timeAxis <= tl(2);
end

% Optional beam subset.
beamMask = true(nBeam, 1);
if isfield(PeakParams, 'BeamAnglesToUse') && ~isempty(PeakParams.BeamAnglesToUse)
    targetAngles = double(PeakParams.BeamAnglesToUse(:));
    tol = double(getFieldOrDefaultLocal(PeakParams, 'BeamAngleTolerance', 1e-6));
    beamMask = false(nBeam, 1);
    for ia = 1:numel(targetAngles)
        beamMask = beamMask | abs(scanAngles - targetAngles(ia)) <= tol;
    end
end

% Global visibility floor. For dB-normalized BTR this is typically -35 dB.
globalMaxLin = max(BTRlin(:));
relativeThresholdLin = globalMaxLin * 10^(relativeThresholdDB / 10);

rows = {};
perBeamPeakCount = zeros(nBeam, 1);
perBeamFirstPeak = nan(nBeam, 1);
perBeamMeanInterval = nan(nBeam, 1);
perBeamPeakTimes = cell(nBeam, 1);
perBeamThresholdMedianDB = nan(nBeam, 1);

for ib = 1:nBeam
    if ~beamMask(ib)
        continue;
    end

    x = BTRlin(ib, :);
    if smoothPts > 1
        xSmooth = movmean(x, smoothPts, 2, 'omitnan');
    else
        xSmooth = x;
    end

    xSmooth(~isfinite(xSmooth)) = 0;
    xSmooth(~timeMask) = 0;

    localNoise = estimateLocalNoiseLocal(xSmooth, trainPts, guardPts, noisePercentile);
    localNoise = max(localNoise, eps);

    switch thresholdMode
        case 'relative'
            thr = relativeThresholdLin * ones(size(xSmooth));
        case 'cfar'
            thr = cfarFactor * localNoise;
        case 'hybrid'
            thr = max(relativeThresholdLin, cfarFactor * localNoise);
        otherwise
            error('ExtractBTRPeaks:InvalidThresholdMode', 'ThresholdMode 必须为 hybrid、relative 或 cfar。');
    end

    perBeamThresholdMedianDB(ib) = 10 * log10(median(thr(timeMask), 'omitnan') + eps);

    promLin = 10^(minPromDB/10) * localNoise;
    isPeak = false(1, nTime);
    if nTime >= 3
        isPeak(2:nTime-1) = xSmooth(2:nTime-1) >= xSmooth(1:nTime-2) & ...
                            xSmooth(2:nTime-1) >  xSmooth(3:nTime) & ...
                            xSmooth(2:nTime-1) >  thr(2:nTime-1) & ...
                            xSmooth(2:nTime-1) >  promLin(2:nTime-1) & ...
                            timeMask(2:nTime-1);
    end

    candIdx = find(isPeak);
    if isempty(candIdx)
        continue;
    end

    % Greedy non-maximum suppression by peak height.
    [~, order] = sort(xSmooth(candIdx), 'descend');
    candIdx = candIdx(order);
    keep = false(size(candIdx));
    keptIdx = [];
    for kk = 1:numel(candIdx)
        idx = candIdx(kk);
        if isempty(keptIdx) || all(abs(idx - keptIdx) >= minDistPts)
            keep(kk) = true;
            keptIdx(end+1) = idx; %#ok<AGROW>
        end
    end
    peakIdx = candIdx(keep);
    [~, sortTimeOrder] = sort(timeAxis(peakIdx), 'ascend');
    peakIdx = peakIdx(sortTimeOrder);

    if isfinite(maxPeaks) && numel(peakIdx) > maxPeaks
        % Keep the strongest MaxNumPeaksPerBeam, then sort by time again.
        [~, orderStrong] = sort(xSmooth(peakIdx), 'descend');
        peakIdx = peakIdx(orderStrong(1:round(maxPeaks)));
        [~, sortTimeOrder] = sort(timeAxis(peakIdx), 'ascend');
        peakIdx = peakIdx(sortTimeOrder);
    end

    peakTimes = timeAxis(peakIdx).';
    peakValsLin = xSmooth(peakIdx).';
    peakValsDB = 10 * log10(peakValsLin + eps);
    localNoiseDB = 10 * log10(localNoise(peakIdx).' + eps);
    promDB = peakValsDB - localNoiseDB;
    thrDB = 10 * log10(thr(peakIdx).' + eps);
    intervalPrev = [NaN; diff(peakTimes)];
    intervalNext = [diff(peakTimes); NaN];

    perBeamPeakCount(ib) = numel(peakIdx);
    perBeamPeakTimes{ib} = peakTimes;
    if ~isempty(peakTimes)
        perBeamFirstPeak(ib) = peakTimes(1);
    end
    if numel(peakTimes) >= 2
        perBeamMeanInterval(ib) = mean(diff(peakTimes), 'omitnan');
    end

    for ip = 1:numel(peakIdx)
        rows(end+1, :) = { ... %#ok<AGROW>
            ib, scanAngles(ib), ip, peakTimes(ip), peakValsDB(ip), peakValsLin(ip), ...
            localNoiseDB(ip), promDB(ip), intervalPrev(ip), intervalNext(ip), thrDB(ip)};
    end
end

varNames = {'BeamIndex','ScanAngle','PeakIndex','PeakTime','PeakValueDB', ...
            'PeakValueLinear','LocalNoiseDB','ProminenceDB', ...
            'PeakIntervalPrev','PeakIntervalNext','ThresholdDB'};
if isempty(rows)
    PeakTable = array2table(zeros(0, numel(varNames)), 'VariableNames', varNames);
else
    % rows is an N-by-M cell array of numeric scalars. Some MATLAB versions
    % auto-convert cell2table columns to double, while others keep cell columns.
    % Build the numeric matrix explicitly to avoid cell2mat version-dependent failures.
    rowsMat = nan(size(rows, 1), numel(varNames));
    for rr = 1:size(rows, 1)
        for cc = 1:numel(varNames)
            rowsMat(rr, cc) = double(rows{rr, cc});
        end
    end
    PeakTable = array2table(rowsMat, 'VariableNames', varNames);
end

BeamSummary = table((1:nBeam).', scanAngles(:), perBeamPeakCount, perBeamFirstPeak, ...
    perBeamMeanInterval, perBeamThresholdMedianDB, ...
    'VariableNames', {'BeamIndex','ScanAngle','NumPeaks','FirstPeakTime','MeanPeakInterval','MedianThresholdDB'});

PeakInfo = struct();
PeakInfo.NumBeams = nBeam;
PeakInfo.NumTimePoints = nTime;
PeakInfo.NumDetectedPeaks = height(PeakTable);
PeakInfo.TimeStep = dt;
PeakInfo.CFARFactor = cfarFactor;
PeakInfo.CFARFactorDB = 10 * log10(cfarFactor);
PeakInfo.RelativeThresholdDB = relativeThresholdDB;
PeakInfo.ThresholdMode = thresholdMode;
PeakInfo.SmoothPoints = smoothPts;
PeakInfo.TrainingPoints = trainPts;
PeakInfo.GuardPoints = guardPts;
PeakInfo.MinPeakDistancePoints = minDistPts;
PeakInfo.BeamSummary = BeamSummary;
PeakInfo.PerBeamPeakTimes = perBeamPeakTimes;
PeakInfo.Params = PeakParams;

if verbose
    fprintf('ExtractBTRPeaks: detected %d peaks across %d beams.\n', height(PeakTable), nBeam);
end
end

% -------------------------------------------------------------------------
function localNoise = estimateLocalNoiseLocal(x, trainPts, guardPts, pct)
    n = numel(x);
    localNoise = nan(1, n);
    x = double(x(:).');
    for it = 1:n
        iL1 = max(1, it - guardPts - trainPts);
        iL2 = max(1, it - guardPts - 1);
        iR1 = min(n, it + guardPts + 1);
        iR2 = min(n, it + guardPts + trainPts);
        train = [];
        if iL2 >= iL1
            train = [train, x(iL1:iL2)]; %#ok<AGROW>
        end
        if iR2 >= iR1
            train = [train, x(iR1:iR2)]; %#ok<AGROW>
        end
        train = train(isfinite(train) & train > 0);
        if isempty(train)
            localNoise(it) = median(x(isfinite(x) & x > 0), 'omitnan');
        else
            localNoise(it) = percentileLocal(train, pct);
        end
    end
    fallback = median(x(isfinite(x) & x > 0), 'omitnan');
    if ~isfinite(fallback) || fallback <= 0
        fallback = eps;
    end
    localNoise(~isfinite(localNoise) | localNoise <= 0) = fallback;
end

function y = percentileLocal(x, p)
    x = sort(double(x(:)));
    if isempty(x)
        y = NaN;
        return;
    end
    p = max(0, min(100, p));
    pos = 1 + (numel(x)-1) * p / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        y = x(lo);
    else
        y = x(lo) + (x(hi)-x(lo)) * (pos-lo);
    end
end

function v = getFieldOrDefaultLocal(S, name, defaultValue)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = defaultValue;
    end
end
