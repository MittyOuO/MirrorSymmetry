function [ErrorTable, GlobalError] = MatchBTRPeaks(PeakTableSim, PeakTableMeas, MatchParams)
% MatchBTRPeaks  Match BTR visible peaks and calculate arrival-time error.
%
%   [ErrorTable, GlobalError] = MatchBTRPeaks(PeakTableSim, PeakTableMeas, MatchParams)
%
% This function implements the feature-based validation logic used for the
% BTR peak arrival-time metric: peaks are matched per beam, and peak-interval
% consistency is used as a physical constraint before calculating absolute
% arrival-time error.
%
% Inputs
%   PeakTableSim   : table returned by ExtractBTRPeaks for simulation.
%   PeakTableMeas  : table returned by ExtractBTRPeaks for measurement.
%   MatchParams    : optional struct fields
%       TauInterval          interval-consistency tolerance, seconds (default 0.25)
%       MaxAbsTimeDiff       optional absolute-time gate, seconds (default Inf)
%       PassThreshold        global pass threshold, seconds (default 0.5)
%       BeamAngleTolerance   angle matching tolerance, deg (default 1e-6)
%       WeightMode           'matchedCount' (default), 'beamImportance', 'uniform'
%       BeamWeights          optional table/struct/vector for beam weights
%       UseNextForFirstPeak  use next interval for first peak signature (default true)
%       AllowSinglePeakMatch allow match when one/both beams have single peak (default false)
%       Verbose              true/false (default false)
%
% Outputs
%   ErrorTable     : matched peak-pair table.
%   GlobalError    : struct with PerBeam table, Eglobal, PassFlag, etc.

if nargin < 3 || isempty(MatchParams)
    MatchParams = struct();
end
validatePeakTableLocal(PeakTableSim, 'PeakTableSim');
validatePeakTableLocal(PeakTableMeas, 'PeakTableMeas');

tauInterval = double(getFieldOrDefaultLocal(MatchParams, 'TauInterval', 0.25));
maxAbsTimeDiff = double(getFieldOrDefaultLocal(MatchParams, 'MaxAbsTimeDiff', Inf));
passThreshold = double(getFieldOrDefaultLocal(MatchParams, 'PassThreshold', 0.5));
angleTol = double(getFieldOrDefaultLocal(MatchParams, 'BeamAngleTolerance', 1e-6));
weightMode = lower(char(getFieldOrDefaultLocal(MatchParams, 'WeightMode', 'matchedCount')));
useNextForFirst = logical(getFieldOrDefaultLocal(MatchParams, 'UseNextForFirstPeak', true));
allowSingle = logical(getFieldOrDefaultLocal(MatchParams, 'AllowSinglePeakMatch', false));
verbose = logical(getFieldOrDefaultLocal(MatchParams, 'Verbose', false));

simAngles = unique(PeakTableSim.ScanAngle);
measAngles = unique(PeakTableMeas.ScanAngle);
beamAngles = [];
for ia = 1:numel(measAngles)
    if any(abs(simAngles - measAngles(ia)) <= angleTol)
        beamAngles(end+1, 1) = measAngles(ia); %#ok<AGROW>
    end
end
beamAngles = unique(beamAngles);

rows = {};
beamRows = {};

for ibeam = 1:numel(beamAngles)
    theta = beamAngles(ibeam);
    measMask = abs(PeakTableMeas.ScanAngle - theta) <= angleTol;
    simMask = abs(PeakTableSim.ScanAngle - theta) <= angleTol;

    Tobs = sortrows(PeakTableMeas(measMask, :), 'PeakTime');
    Tsim = sortrows(PeakTableSim(simMask, :), 'PeakTime');

    nObs = height(Tobs);
    nSim = height(Tsim);
    if nObs == 0 || nSim == 0
        beamRows(end+1, :) = {theta, nObs, nSim, 0, NaN, NaN, NaN, 0}; %#ok<AGROW>
        continue;
    end

    obsTimes = Tobs.PeakTime(:);
    simTimes = Tsim.PeakTime(:);
    obsSig = peakIntervalSignatureLocal(obsTimes, useNextForFirst);
    simSig = peakIntervalSignatureLocal(simTimes, useNextForFirst);

    candidate = false(nObs, nSim);
    intervalErr = nan(nObs, nSim);
    absErr = abs(obsTimes - simTimes.');
    for io = 1:nObs
        for js = 1:nSim
            if absErr(io, js) > maxAbsTimeDiff
                continue;
            end
            if isfinite(obsSig(io)) && isfinite(simSig(js))
                intervalErr(io, js) = abs(obsSig(io) - simSig(js));
                candidate(io, js) = intervalErr(io, js) <= tauInterval;
            elseif allowSingle
                intervalErr(io, js) = NaN;
                candidate(io, js) = true;
            end
        end
    end

    matchPairs = solveOrderedMatchingLocal(candidate, absErr);
    K = size(matchPairs, 1);

    if K == 0
        beamErr = NaN;
        medErr = NaN;
        maxErr = NaN;
    else
        pairAbsErr = zeros(K, 1);
        pairIntErr = nan(K, 1);
        for k = 1:K
            io = matchPairs(k, 1);
            js = matchPairs(k, 2);
            pairAbsErr(k) = absErr(io, js);
            pairIntErr(k) = intervalErr(io, js);

            rows(end+1, :) = { ... %#ok<AGROW>
                theta, k, io, js, obsTimes(io), simTimes(js), pairAbsErr(k), ...
                obsSig(io), simSig(js), pairIntErr(k), ...
                getOptionalColumnValueLocal(Tobs, 'PeakValueDB', io, NaN), ...
                getOptionalColumnValueLocal(Tsim, 'PeakValueDB', js, NaN)};
        end
        beamErr = mean(pairAbsErr, 'omitnan');
        medErr = median(pairAbsErr, 'omitnan');
        maxErr = max(pairAbsErr);
    end

    beamWeight = computeBeamWeightLocal(theta, K, MatchParams, weightMode);
    beamRows(end+1, :) = {theta, nObs, nSim, K, beamErr, medErr, maxErr, beamWeight}; %#ok<AGROW>
end

errVarNames = {'ScanAngle','MatchIndex','ObsPeakIndex','SimPeakIndex', ...
    'ObsPeakTime','SimPeakTime','AbsTimeError','ObsIntervalSignature', ...
    'SimIntervalSignature','IntervalError','ObsPeakValueDB','SimPeakValueDB'};
if isempty(rows)
    ErrorTable = array2table(zeros(0, numel(errVarNames)), 'VariableNames', errVarNames);
else
    rowsMat = nan(size(rows, 1), numel(errVarNames));
    for rr = 1:size(rows, 1)
        for cc = 1:numel(errVarNames)
            rowsMat(rr, cc) = double(rows{rr, cc});
        end
    end
    ErrorTable = array2table(rowsMat, 'VariableNames', errVarNames);
end

beamVarNames = {'ScanAngle','NumObsPeaks','NumSimPeaks','NumMatchedPairs', ...
    'MeanAbsError','MedianAbsError','MaxAbsError','BeamWeight'};
if isempty(beamRows)
    PerBeam = array2table(zeros(0, numel(beamVarNames)), 'VariableNames', beamVarNames);
else
    beamRowsMat = nan(size(beamRows, 1), numel(beamVarNames));
    for rr = 1:size(beamRows, 1)
        for cc = 1:numel(beamVarNames)
            beamRowsMat(rr, cc) = double(beamRows{rr, cc});
        end
    end
    PerBeam = array2table(beamRowsMat, 'VariableNames', beamVarNames);
end

validBeam = isfinite(PerBeam.MeanAbsError) & PerBeam.NumMatchedPairs > 0 & PerBeam.BeamWeight > 0;
if any(validBeam)
    Eglobal = sum(PerBeam.BeamWeight(validBeam) .* PerBeam.MeanAbsError(validBeam)) / ...
              sum(PerBeam.BeamWeight(validBeam));
else
    Eglobal = NaN;
end

GlobalError = struct();
GlobalError.Eglobal = Eglobal;
GlobalError.PassThreshold = passThreshold;
GlobalError.PassFlag = isfinite(Eglobal) && Eglobal <= passThreshold;
GlobalError.NumMatchedPairs = height(ErrorTable);
GlobalError.NumMatchedBeams = sum(validBeam);
GlobalError.NumCommonBeams = numel(beamAngles);
GlobalError.PerBeam = PerBeam;
GlobalError.TauInterval = tauInterval;
GlobalError.MaxAbsTimeDiff = maxAbsTimeDiff;
GlobalError.WeightMode = weightMode;
GlobalError.Params = MatchParams;
GlobalError.Available = any(validBeam);
if GlobalError.Available
    GlobalError.Status = 'COMPUTED';
    GlobalError.Reason = '';
else
    GlobalError.Status = 'NOT_COMPUTED';
    GlobalError.Reason = 'Insufficient interval-supported peak associations';
end

if verbose
    fprintf('MatchBTRPeaks: matched %d peak pairs over %d beams; Eglobal=%.4f s.\n', ...
        GlobalError.NumMatchedPairs, GlobalError.NumMatchedBeams, Eglobal);
end
end

% -------------------------------------------------------------------------
function sig = peakIntervalSignatureLocal(t, useNextForFirst)
    t = t(:);
    n = numel(t);
    sig = nan(n, 1);
    if n < 2
        return;
    end
    for k = 1:n
        if k > 1
            sig(k) = t(k) - t(k-1);
        elseif useNextForFirst
            sig(k) = t(2) - t(1);
        end
    end
end

function pairs = solveOrderedMatchingLocal(candidate, cost)
% Dynamic programming for order-preserving peak matching.
% Objective: maximize number of matched pairs, then minimize total cost.
    [nObs, nSim] = size(candidate);
    num = zeros(nObs+1, nSim+1);
    totalCost = inf(nObs+1, nSim+1);
    totalCost(1, :) = 0;
    totalCost(:, 1) = 0;
    move = zeros(nObs+1, nSim+1); % 1 skip obs, 2 skip sim, 3 match

    for i = 2:nObs+1
        for j = 2:nSim+1
            optsNum = [num(i-1,j), num(i,j-1), -Inf];
            optsCost = [totalCost(i-1,j), totalCost(i,j-1), Inf];
            if candidate(i-1, j-1)
                optsNum(3) = num(i-1,j-1) + 1;
                optsCost(3) = totalCost(i-1,j-1) + cost(i-1,j-1);
            end
            % Choose max matches; among ties choose min total cost.
            maxN = max(optsNum);
            idxTie = find(optsNum == maxN);
            [~, bestLocal] = min(optsCost(idxTie));
            bestMove = idxTie(bestLocal);
            num(i,j) = optsNum(bestMove);
            totalCost(i,j) = optsCost(bestMove);
            move(i,j) = bestMove;
        end
    end

    pairs = zeros(0, 2);
    i = nObs + 1;
    j = nSim + 1;
    while i > 1 && j > 1
        if move(i,j) == 3
            pairs(end+1, :) = [i-1, j-1]; %#ok<AGROW>
            i = i - 1;
            j = j - 1;
        elseif move(i,j) == 1
            i = i - 1;
        else
            j = j - 1;
        end
    end
    pairs = flipud(pairs);
end

function w = computeBeamWeightLocal(theta, K, MatchParams, weightMode)
    switch weightMode
        case {'matchedcount','k','peakcount'}
            w = K;
        case 'uniform'
            w = double(K > 0);
        case {'beamimportance','custom'}
            w = lookupBeamWeightLocal(theta, MatchParams);
            if ~isfinite(w) || w <= 0
                w = K;
            end
        otherwise
            w = K;
    end
end

function w = lookupBeamWeightLocal(theta, MatchParams)
    w = NaN;
    if ~isfield(MatchParams, 'BeamWeights') || isempty(MatchParams.BeamWeights)
        return;
    end
    BW = MatchParams.BeamWeights;
    if istable(BW)
        if all(ismember({'ScanAngle','Weight'}, BW.Properties.VariableNames))
            [mindiff, idx] = min(abs(BW.ScanAngle - theta));
            if mindiff <= getFieldOrDefaultLocal(MatchParams, 'BeamAngleTolerance', 1e-6)
                w = BW.Weight(idx);
            end
        end
    elseif isnumeric(BW)
        if isscalar(BW)
            w = BW;
        end
    elseif isstruct(BW) && isfield(BW, 'ScanAngle') && isfield(BW, 'Weight')
        [mindiff, idx] = min(abs(BW.ScanAngle(:) - theta));
        if mindiff <= getFieldOrDefaultLocal(MatchParams, 'BeamAngleTolerance', 1e-6)
            w = BW.Weight(idx);
        end
    end
end

function v = getOptionalColumnValueLocal(T, colName, idx, defaultValue)
    if istable(T) && ismember(colName, T.Properties.VariableNames)
        v = T.(colName)(idx);
    else
        v = defaultValue;
    end
end

function validatePeakTableLocal(T, name)
    if ~istable(T)
        error('MatchBTRPeaks:InvalidPeakTable', '%s 必须为 table。', name);
    end
    req = {'ScanAngle','PeakTime'};
    for i = 1:numel(req)
        if ~ismember(req{i}, T.Properties.VariableNames)
            error('MatchBTRPeaks:MissingColumn', '%s 缺少列 %s。', name, req{i});
        end
    end
end

function v = getFieldOrDefaultLocal(S, name, defaultValue)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = defaultValue;
    end
end
