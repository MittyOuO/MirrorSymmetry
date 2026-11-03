function model = BuildBeamWeightModelV2(pattern2D, domainType)
%BuildBeamWeightModelV2 Build the auditable V2 beam-weight hierarchy.
%   MODEL = BuildBeamWeightModelV2(PATTERN2D, DOMAINTYPE) separates the
%   interpolated -3 dB main-lobe core, optional real-pattern skirts, every
%   secondary lobe above the internal classification threshold, and the
%   residual energy-equivalent side regions.  DOMAINTYPE is 'bounded' for
%   elevation and 'circular' for azimuth.

thresholdDB = -3;                 % Internal, intentionally not a UI input.
thresholdAmp = 10^(thresholdDB/20);

[ang, amp] = readPatternLocal(pattern2D);
if nargin < 2 || isempty(domainType)
    if isfield(pattern2D, 'cutName') && strcmpi(string(pattern2D.cutName), "azimuth")
        domainType = 'circular';
    else
        domainType = 'bounded';
    end
end
domainType = lower(char(string(domainType)));
if ~ismember(domainType, {'bounded','circular'})
    error('BuildBeamWeightModelV2:DomainType', ...
        'domainType must be bounded or circular.');
end

center = scalarFieldLocal(pattern2D, {'centerAngle','center','steerAngle'}, ang(argmaxLocal(amp)));
left3 = scalarFieldLocal(pattern2D, {'left3dB','Left3dB','leftHP','leftBoundary'}, NaN);
right3 = scalarFieldLocal(pattern2D, {'right3dB','Right3dB','rightHP','rightBoundary'}, NaN);
if ~all(isfinite([left3 right3]))
    error('BuildBeamWeightModelV2:Missing3dBBounds', ...
        'Pattern2D must contain finite interpolated left3dB/right3dB bounds.');
end

if strcmp(domainType, 'circular')
    [angWork, ampWork] = uniquePeriodicPatternLocal(ang, amp);
    relWork = wrap180Local(angWork - center);
    [relWork, order] = sort(relWork);
    ampWork = ampWork(order);
    angWork = center + relWork;
    leftRel = negativeRelativeLocal(left3, center);
    rightRel = positiveRelativeLocal(right3, center);
else
    angWork = ang;
    ampWork = amp;
    relWork = angWork - center;
    leftRel = left3 - center;
    rightRel = right3 - center;
end

if leftRel > 1e-9 || rightRel < -1e-9
    error('BuildBeamWeightModelV2:Invalid3dBBounds', ...
        'The -3 dB bounds must straddle the main-lobe center.');
end

minIdx = localMinimaLocal(ampWork, strcmp(domainType, 'circular'));
maxIdx = localMaximaLocal(ampWork, strcmp(domainType, 'circular'));

[leftBoundaryLimited, rightBoundaryLimited] = boundaryFlagsLocal(pattern2D, ...
    domainType, left3, right3, angWork);
[leftNullRel, leftNullIdx] = nearestMinimumLocal(relWork, minIdx, leftRel, -1);
[rightNullRel, rightNullIdx] = nearestMinimumLocal(relWork, minIdx, rightRel, +1);

if leftBoundaryLimited
    leftNullRel = NaN; leftNullIdx = NaN;
end
if rightBoundaryLimited
    rightNullRel = NaN; rightNullIdx = NaN;
end

main = struct();
main.CenterDeg = normalizeOutputAngleLocal(center, domainType);
main.Left3dBDeg = normalizeOutputAngleLocal(center + leftRel, domainType);
main.Right3dBDeg = normalizeOutputAngleLocal(center + rightRel, domainType);
main.Left3dBOffsetDeg = leftRel;
main.Right3dBOffsetDeg = rightRel;
main.PeakAmplitude = 1;
main.PeakGain_dB = 0;
main.CoreRangeDeg = [main.Left3dBDeg main.Right3dBDeg];
main.LeftSkirt = skirtLocal(center, leftRel, leftNullRel, leftNullIdx, ...
    ampWork, domainType, leftBoundaryLimited, 'left');
main.RightSkirt = skirtLocal(center, rightRel, rightNullRel, rightNullIdx, ...
    ampWork, domainType, rightBoundaryLimited, 'right');

leftSupportRel = chooseSupportLocal(leftNullRel, leftRel);
rightSupportRel = chooseSupportLocal(rightNullRel, rightRel);
main.SupportRangeDeg = [normalizeOutputAngleLocal(center + leftSupportRel, domainType), ...
    normalizeOutputAngleLocal(center + rightSupportRel, domainType)];

secondary = struct('CenterDeg',{},'PeakAmplitude',{},'PeakGain_dB',{}, ...
    'LeftNullDeg',{},'RightNullDeg',{},'SupportRangeDeg',{}, ...
    'Left3dBDeg',{},'Right3dBDeg',{},'Left3dBOffsetDeg',{}, ...
    'Right3dBOffsetDeg',{},'NullType',{}, ...
    'BoundaryLimitedLeft',{},'BoundaryLimitedRight',{});
for k = reshape(maxIdx, 1, [])
    relPeak = relWork(k);
    peakAmp = ampWork(k);
    if relPeak >= leftSupportRel && relPeak <= rightSupportRel
        continue;
    end
    if peakAmp + 1e-12 < thresholdAmp
        continue;
    end

    isCircular = strcmp(domainType, 'circular');
    [lNull, lIdx] = nearestMinimumLocal(relWork - relPeak, minIdx, 0, -1, relWork, relPeak, isCircular);
    [rNull, rIdx] = nearestMinimumLocal(relWork - relPeak, minIdx, 0, +1, relWork, relPeak, isCircular);
    if ~all(isfinite([lNull rNull lIdx rIdx])) || lNull >= relPeak || rNull <= relPeak
        continue;
    end

    relativeThreshold = peakAmp / sqrt(2);
    boundaryLimitedLeft = ~isCircular && lIdx == 1;
    boundaryLimitedRight = ~isCircular && rIdx == numel(angWork);
    if isCircular
        aExt = [angWork-360; angWork; angWork+360];
        yExt = repmat(ampWork,3,1);
        peakAngle = center + relPeak;
        [~, peakExt] = min(abs(aExt-peakAngle));
        [~, leftExt] = min(abs(aExt-(center+lNull)));
        [~, rightExt] = min(abs(aExt-(center+rNull)));
        l3 = crossingLocal(aExt,yExt,peakExt,leftExt,relativeThreshold,-1);
        r3 = crossingLocal(aExt,yExt,peakExt,rightExt,relativeThreshold,+1);
    else
        l3 = crossingLocal(angWork, ampWork, k, lIdx, relativeThreshold, -1);
        r3 = crossingLocal(angWork, ampWork, k, rIdx, relativeThreshold, +1);
    end
    if ~isfinite(l3) && boundaryLimitedLeft
        l3 = angWork(1);
    end
    if ~isfinite(r3) && boundaryLimitedRight
        r3 = angWork(end);
    end
    if ~all(isfinite([l3 r3])) || l3 >= angWork(k) || r3 <= angWork(k)
        continue;
    end

    item = struct();
    item.CenterDeg = normalizeOutputAngleLocal(angWork(k), domainType);
    item.PeakAmplitude = peakAmp;
    item.PeakGain_dB = 20*log10(max(peakAmp, realmin));
    % lNull/rNull use the same relative-to-main-center coordinates as
    % relWork.  Convert them back to absolute cut angles before storing.
    item.LeftNullDeg = normalizeOutputAngleLocal(center + lNull, domainType);
    item.RightNullDeg = normalizeOutputAngleLocal(center + rNull, domainType);
    item.SupportRangeDeg = [item.LeftNullDeg item.RightNullDeg];
    item.Left3dBDeg = normalizeOutputAngleLocal(l3, domainType);
    item.Right3dBDeg = normalizeOutputAngleLocal(r3, domainType);
    item.Left3dBOffsetDeg = l3 - angWork(k);
    item.Right3dBOffsetDeg = r3 - angWork(k);
    item.NullType = {secondaryNullTypeLocal(ampWork(lIdx),boundaryLimitedLeft), ...
        secondaryNullTypeLocal(ampWork(rIdx),boundaryLimitedRight)};
    item.BoundaryLimitedLeft = boundaryLimitedLeft;
    item.BoundaryLimitedRight = boundaryLimitedRight;
    assertSecondaryInvariantLocal(item,domainType);
    secondary(end+1) = item; %#ok<AGROW>
end

% Deterministic order: increasing signed offset from the main center.
if ~isempty(secondary)
    secRel = arrayfun(@(s) signedRelativeLocal(s.CenterDeg, center, domainType), secondary);
    [~, order] = sort(secRel);
    secondary = secondary(order);
end

excluded = false(size(angWork));
excluded = excluded | relWork >= leftSupportRel & relWork <= rightSupportRel;
for k = 1:numel(secondary)
    excluded = excluded | inRangeLocal(angWork, secondary(k).SupportRangeDeg, domainType);
end

negMask = relWork < leftSupportRel & ~excluded;
posMask = relWork > rightSupportRel & ~excluded;
if strcmp(domainType,'bounded')
    negativeRange = [min(angWork), center + leftSupportRel];
    positiveRange = [center + rightSupportRel, max(angWork)];
else
    negativeRange = [center-180, center+leftSupportRel];
    positiveRange = [center+rightSupportRel, center+180];
end
negative = residualLocal(angWork,ampWork,negMask,negativeRange,domainType);
positive = residualLocal(angWork,ampWork,posMask,positiveRange,domainType);

residual = struct('NegativeSide',negative,'PositiveSide',positive);
if strcmp(domainType, 'circular')
    residual.Left = negative;
    residual.Right = positive;
else
    residual.Lower = negative;
    residual.Upper = positive;
end

model = struct();
model.Version = 2;
model.DomainType = domainType;
model.SecondaryMainLobeThreshold_dB = thresholdDB;
model.Main = main;
model.SecondaryLobes = secondary;
model.ResidualSide = residual;
model.PatternAngles = ang(:).';
model.PatternAmplitude = amp(:).';
if isfield(pattern2D, 'cutName'), model.CutName = pattern2D.cutName; else, model.CutName = ''; end
if strcmp(domainType,'bounded')
    validateBoundedModelLocal(model,min(angWork),max(angWork));
end
end

function [ang, amp] = readPatternLocal(P)
ang = fieldLocal(P, {'scanAngles','angles','theta','phi','x'});
amp = fieldLocal(P, {'AF','A','Pattern','pattern','amp','Amplitude','y'});
ang = double(ang(:)); amp = abs(double(amp(:)));
valid = isfinite(ang) & isfinite(amp);
ang = ang(valid); amp = amp(valid);
if numel(ang) < 5 || numel(ang) ~= numel(amp)
    error('BuildBeamWeightModelV2:InvalidPattern', 'Pattern2D must contain at least five finite samples.');
end
[ang, order] = sort(ang); amp = amp(order);
[ang, ia] = unique(ang, 'stable'); amp = amp(ia);
peak = max(amp);
if ~(isfinite(peak) && peak > 0)
    error('BuildBeamWeightModelV2:ZeroPattern', 'Pattern2D amplitude has no positive finite peak.');
end
amp = amp ./ peak;
end

function v = fieldLocal(S, names)
v = [];
for k = 1:numel(names)
    if isfield(S, names{k}) && ~isempty(S.(names{k}))
        v = S.(names{k}); return;
    end
end
error('BuildBeamWeightModelV2:MissingPatternField', 'Pattern2D is missing a required field.');
end

function v = scalarFieldLocal(S, names, defaultValue)
v = defaultValue;
for k = 1:numel(names)
    if isfield(S, names{k}) && ~isempty(S.(names{k}))
        candidate = double(S.(names{k}));
        if isfinite(candidate(1)), v = candidate(1); end
        return;
    end
end
end

function idx = argmaxLocal(x)
[~, idx] = max(x);
end

function [a, y] = uniquePeriodicPatternLocal(a, y)
tol = max(1e-9, 1e-8*max(1,range(a)));
if numel(a) > 2 && abs((a(end)-a(1))-360) <= tol
    a = a(1:end-1); y = y(1:end-1);
end
end

function idx = localMinimaLocal(y, circular)
n = numel(y); idx = [];
if n < 3, return; end
if circular
    left = y([n 1:n-1]); right = y([2:n 1]);
    idx = find(y <= left & y <= right & (y < left | y < right));
else
    idx = find(y(2:end-1) <= y(1:end-2) & y(2:end-1) <= y(3:end) & ...
        (y(2:end-1) < y(1:end-2) | y(2:end-1) < y(3:end))) + 1;
    if y(1) <= y(2), idx = [1; idx(:)]; end
    if y(end) <= y(end-1), idx = [idx(:); n]; end
end
end

function idx = localMaximaLocal(y, circular)
n = numel(y); idx = [];
if n < 3, return; end
if circular
    left = y([n 1:n-1]); right = y([2:n 1]);
    idx = find(y >= left & y >= right & (y > left | y > right));
else
    idx = find(y(2:end-1) >= y(1:end-2) & y(2:end-1) >= y(3:end) & ...
        (y(2:end-1) > y(1:end-2) | y(2:end-1) > y(3:end))) + 1;
end
end

function [limitedL, limitedR] = boundaryFlagsLocal(P, domainType, left3, right3, a)
limitedL = false; limitedR = false;
if strcmp(domainType, 'circular'), return; end
if isfield(P, 'HPBWAudit') && isstruct(P.HPBWAudit)
    H = P.HPBWAudit;
    limitedL = logical(scalarFieldLocal(H, {'leftBoundaryLimited'}, false));
    limitedR = logical(scalarFieldLocal(H, {'rightBoundaryLimited'}, false));
end
tol = max(1e-6, 1.5*median(diff(a)));
limitedL = limitedL || abs(left3 - a(1)) <= tol;
limitedR = limitedR || abs(right3 - a(end)) <= tol;
end

function [value, idx] = nearestMinimumLocal(rel, minIdx, boundary, direction, varargin)
value = NaN; idx = NaN;
if isempty(minIdx), return; end
if nargin >= 6
    baseRel = varargin{1}; peakRel = varargin{2};
    circular = numel(varargin) >= 3 && logical(varargin{3});
    candidates = baseRel(minIdx);
    if circular
        delta = wrap180Local(candidates-peakRel);
        if direction < 0
            delta(delta >= 0) = NaN;
            [bestDelta,q] = max(delta,[],'omitnan');
        else
            delta(delta <= 0) = NaN;
            [bestDelta,q] = min(delta,[],'omitnan');
        end
        if isempty(q) || ~isfinite(bestDelta)
            value=NaN; idx=NaN;
        else
            value=peakRel+bestDelta; idx=minIdx(q);
        end
        return;
    end
    if direction < 0
        candidates(candidates >= peakRel) = NaN;
        [value, q] = max(candidates, [], 'omitnan');
    else
        candidates(candidates <= peakRel) = NaN;
        [value, q] = min(candidates, [], 'omitnan');
    end
    if isempty(q) || ~isfinite(value), value = NaN; idx = NaN; else, idx = minIdx(q); end
    return;
end
candidates = rel(minIdx);
if direction < 0
    candidates(candidates >= boundary) = NaN;
    [value, q] = max(candidates, [], 'omitnan');
else
    candidates(candidates <= boundary) = NaN;
    [value, q] = min(candidates, [], 'omitnan');
end
if isempty(q) || ~isfinite(value), value = NaN; idx = NaN; else, idx = minIdx(q); end
end

function S = skirtLocal(center, edgeRel, nullRel, nullIdx, amp, domainType, limited, side)
enabled = isfinite(nullRel) && isfinite(nullIdx) && ~limited;
S = struct('Enabled',enabled,'RangeDeg',[NaN NaN],'NullAngleDeg',NaN, ...
    'NullAmplitude',NaN,'NullType','none','BoundaryLimited',logical(limited), ...
    'Side',side);
if ~enabled, return; end
if edgeRel < nullRel, tmp=edgeRel; edgeRel=nullRel; nullRel=tmp; end
S.RangeDeg = [normalizeOutputAngleLocal(center + nullRel, domainType), ...
    normalizeOutputAngleLocal(center + edgeRel, domainType)];
S.NullAngleDeg = normalizeOutputAngleLocal(center + nullRel, domainType);
S.NullAmplitude = amp(nullIdx);
S.NullType = nullTypeLocal(amp(nullIdx));
end

function type = nullTypeLocal(v)
if v <= 1e-6, type = 'exact_or_near_zero'; else, type = 'stable_local_minimum'; end
end

function type = secondaryNullTypeLocal(v,boundaryLimited)
if boundaryLimited
    type = 'physical_boundary';
else
    type = nullTypeLocal(v);
end
end

function assertSecondaryInvariantLocal(L,domainType)
tol = 1e-7;
if strcmp(domainType,'circular')
    leftNull = L.CenterDeg + negativeRelativeLocal(L.LeftNullDeg,L.CenterDeg);
    left3 = L.CenterDeg + negativeRelativeLocal(L.Left3dBDeg,L.CenterDeg);
    right3 = L.CenterDeg + positiveRelativeLocal(L.Right3dBDeg,L.CenterDeg);
    rightNull = L.CenterDeg + positiveRelativeLocal(L.RightNullDeg,L.CenterDeg);
    center = L.CenterDeg;
else
    leftNull=L.LeftNullDeg; left3=L.Left3dBDeg; center=L.CenterDeg;
    right3=L.Right3dBDeg; rightNull=L.RightNullDeg;
end
if ~(leftNull <= left3+tol && left3 <= center+tol && ...
        center <= right3+tol && right3 <= rightNull+tol)
    error('BuildBeamWeightModelV2:SecondaryCoordinateInvariant', ...
        'Secondary lobe coordinates are inconsistent around center %.6g deg.',L.CenterDeg);
end
end

function validateBoundedModelLocal(model,physicalLower,physicalUpper)
tol=1e-7;
ranges={model.Main.CoreRangeDeg,model.Main.SupportRangeDeg, ...
    model.ResidualSide.NegativeSide.RangeDeg,model.ResidualSide.PositiveSide.RangeDeg};
if model.Main.LeftSkirt.Enabled, ranges{end+1}=model.Main.LeftSkirt.RangeDeg; end %#ok<AGROW>
if model.Main.RightSkirt.Enabled, ranges{end+1}=model.Main.RightSkirt.RangeDeg; end %#ok<AGROW>
for k=1:numel(model.SecondaryLobes)
    ranges{end+1}=model.SecondaryLobes(k).SupportRangeDeg; %#ok<AGROW>
    ranges{end+1}=[model.SecondaryLobes(k).Left3dBDeg model.SecondaryLobes(k).Right3dBDeg]; %#ok<AGROW>
end
for k=1:numel(ranges)
    r=double(ranges{k}); r=r(isfinite(r));
    if any(r<physicalLower-tol) || any(r>physicalUpper+tol)
        error('BuildBeamWeightModelV2:ElevationRangeOutOfBounds', ...
            'Bounded beam range exceeds physical domain [%.6g, %.6g] deg.', ...
            physicalLower,physicalUpper);
    end
end
end

function v = chooseSupportLocal(nullRel, edgeRel)
if isfinite(nullRel), v = nullRel; else, v = edgeRel; end
end

function crossing = crossingLocal(a, y, peakIdx, nullIdx, level, direction)
crossing = NaN;
if direction < 0
    indices = peakIdx:-1:nullIdx;
else
    indices = peakIdx:1:nullIdx;
end
for q = 1:numel(indices)-1
    i1 = indices(q); i2 = indices(q+1);
    if (y(i1)-level)*(y(i2)-level) <= 0 && y(i1) ~= y(i2)
        crossing = a(i1) + (level-y(i1))*(a(i2)-a(i1))/(y(i2)-y(i1));
        return;
    end
end
end

function R = residualLocal(a, y, mask, requestedRange, domainType)
R = struct('Enabled',false,'RangeDeg',[NaN NaN],'LevelAmplitude',0, ...
    'Level_dB',-Inf,'EquivalentEnergy',0,'EquivalentWidthDeg',0);
% Keep the requested physical range auditable even when that side has no
% remaining samples after main/secondary-lobe exclusion.
R.RangeDeg = [normalizeOutputAngleLocal(requestedRange(1),domainType), ...
    normalizeOutputAngleLocal(requestedRange(2),domainType)];
idx = find(mask);
if numel(idx) < 2, return; end
breaks = [0; find(diff(idx)>1); numel(idx)];
energy = 0; width = 0;
for k = 1:numel(breaks)-1
    seg = idx(breaks(k)+1:breaks(k+1));
    if numel(seg) >= 2
        energy = energy + trapz(a(seg), y(seg).^2);
        width = width + a(seg(end))-a(seg(1));
    end
end
if width <= 0, return; end
level = sqrt(max(0,energy/width));
R.Enabled = isfinite(level) && level > 0;
R.LevelAmplitude = level;
R.Level_dB = 20*log10(max(level,realmin));
R.EquivalentEnergy = energy;
R.EquivalentWidthDeg = width;
end

function tf = inRangeLocal(angle, rangeDeg, domainType)
if strcmp(domainType,'circular')
    left = wrap180Local(rangeDeg(1)); right = wrap180Local(rangeDeg(2));
    q = wrap180Local(angle);
    if left <= right, tf = q >= left & q <= right; else, tf = q >= left | q <= right; end
else
    lo=min(rangeDeg); hi=max(rangeDeg); tf=angle>=lo & angle<=hi;
end
end

function value = normalizeOutputAngleLocal(value, domainType)
if strcmp(domainType,'circular'), value=wrap180Local(value); end
end

function d = signedRelativeLocal(angle, center, domainType)
if strcmp(domainType,'circular'), d=wrap180Local(angle-center); else, d=angle-center; end
end

function d = negativeRelativeLocal(angle, center)
d = wrap180Local(angle-center); if d >= 0, d=d-360; end
end

function d = positiveRelativeLocal(angle, center)
d = wrap180Local(angle-center); if d <= 0, d=d+360; end
end

function a = wrap180Local(a)
a = mod(a+180,360)-180;
end
