function varargout = GetBeamWeight(srcAngleDeg, varargin)
%GetBeamWeight Apply independent elevation/azimuth main- and side-lobe rules.
%
% New interface:
%   [ampWeight,powerWeight,regionName,keepFlag] = GetBeamWeight(angle,Beam)
%
% Legacy interface retained for existing model callers:
%   [keepFlag,powerWeight,ampWeight] = GetBeamWeight(angle,phiDeg,Beam)
%
% Elevation fields (model-angle convention):
%   MainBeam          [upper lower]
%   SideRange         [lowerOuter lowerInner; upperInner upperOuter]
%   SideDown_dB       scalar, or [lower upper]
%   ElevSideDown_dB   optional explicit [lower upper] override
%
% Azimuth fields:
%   AzimuthRange       [left right], with wrap-around supported
%   AzimuthSideRange   [leftOuter leftInner; rightInner rightOuter]
%   AzimuthSideDown_dB scalar, or [left right]
%
% Elevation and azimuth weights are evaluated independently and multiplied.
% A zero-width side range is treated as disabled.

if nargin == 2
    phiDeg = 0;
    Beam = varargin{1};
    legacyOrder = false;
elseif nargin == 3
    phiDeg = varargin{1};
    Beam = varargin{2};
    legacyOrder = true;
else
    error('GetBeamWeight:InvalidInput', ...
        'Use GetBeamWeight(angle,Beam) or GetBeamWeight(angle,phiDeg,Beam).');
end
requestedOutputs = nargout;

[mainBeam, sideRange, elevSideDownDb, azRange, ...
    azSideRange, azSideDownDb] = validateInputsLocal(Beam);

ampWeight = 0;
powerWeight = 0;
regionName = 'zero_or_outside';
keepFlag = false;

if ~isnumeric(srcAngleDeg) || ~isscalar(srcAngleDeg) || ~isfinite(srcAngleDeg) || ...
        ~isnumeric(phiDeg) || ~isscalar(phiDeg) || ~isfinite(phiDeg)
    assignOutputsLocal();
    return;
end

[elevAmp, elevPower, elevRegion, elevKeep] = evaluateElevationLocal( ...
    double(srcAngleDeg), mainBeam, sideRange, elevSideDownDb);
if ~elevKeep
    assignOutputsLocal();
    return;
end

[azAmp, azPower, azRegion, azKeep] = evaluateAzimuthLocal( ...
    double(phiDeg), azRange, azSideRange, azSideDownDb);
if ~azKeep
    assignOutputsLocal();
    return;
end

ampWeight = elevAmp * azAmp;
powerWeight = elevPower * azPower;
keepFlag = true;
if strcmp(elevRegion, 'elevation_main_lobe') && strcmp(azRegion, 'azimuth_main_lobe')
    regionName = 'main_lobe';
else
    regionName = [elevRegion, '+', azRegion];
end

assignOutputsLocal();

    function assignOutputsLocal()
        if legacyOrder
            values = {keepFlag, powerWeight, ampWeight, regionName};
        else
            values = {ampWeight, powerWeight, regionName, keepFlag};
        end
        for ii = 1:min(requestedOutputs, numel(values))
            varargout{ii} = values{ii};
        end
    end
end

function [ampWeight, powerWeight, regionName, keepFlag] = ...
        evaluateElevationLocal(angleDeg, mainBeam, sideRange, sideDownDb)
ampWeight = 0;
powerWeight = 0;
regionName = 'elevation_outside';
keepFlag = false;

mainUpper = mainBeam(1);
mainLower = mainBeam(2);
lowerOuter = sideRange(1,1);
lowerInner = sideRange(1,2);
upperInner = sideRange(2,1);
upperOuter = sideRange(2,2);
tol = 1e-9;

if angleDeg >= mainLower-tol && angleDeg <= mainUpper+tol
    [ampWeight, powerWeight] = dbWeightsLocal(0);
    regionName = 'elevation_main_lobe';
    keepFlag = true;
elseif lowerOuter < lowerInner-tol && ...
        angleDeg >= lowerOuter-tol && angleDeg <= lowerInner+tol
    [ampWeight, powerWeight] = dbWeightsLocal(sideDownDb(1));
    regionName = 'elevation_lower_side_lobe';
    keepFlag = true;
elseif upperInner < upperOuter-tol && ...
        angleDeg >= upperInner-tol && angleDeg <= upperOuter+tol
    [ampWeight, powerWeight] = dbWeightsLocal(sideDownDb(2));
    regionName = 'elevation_upper_side_lobe';
    keepFlag = true;
end
end

function [ampWeight, powerWeight, regionName, keepFlag] = ...
        evaluateAzimuthLocal(phiDeg, mainRange, sideRange, sideDownDb)
ampWeight = 0;
powerWeight = 0;
regionName = 'azimuth_outside';
keepFlag = false;

if isAzimuthInRangeLocal(phiDeg, mainRange)
    [ampWeight, powerWeight] = dbWeightsLocal(0);
    regionName = 'azimuth_main_lobe';
    keepFlag = true;
    return;
end

if isempty(sideRange)
    return;
end

if circularWidthLocal(sideRange(1,:)) > 1e-9 && ...
        isAzimuthInRangeLocal(phiDeg, sideRange(1,:))
    [ampWeight, powerWeight] = dbWeightsLocal(sideDownDb(1));
    regionName = 'azimuth_left_side_lobe';
    keepFlag = true;
elseif circularWidthLocal(sideRange(2,:)) > 1e-9 && ...
        isAzimuthInRangeLocal(phiDeg, sideRange(2,:))
    [ampWeight, powerWeight] = dbWeightsLocal(sideDownDb(2));
    regionName = 'azimuth_right_side_lobe';
    keepFlag = true;
end
end

function [ampWeight, powerWeight] = dbWeightsLocal(downDb)
ampWeight = 10^(downDb/20);
powerWeight = 10^(downDb/10);
end

function [mainBeam, sideRange, elevSideDownDb, azRange, ...
        azSideRange, azSideDownDb] = validateInputsLocal(Beam)
if ~isstruct(Beam)
    error('GetBeamWeight:InvalidBeam', 'Beam must be a struct.');
end

mainBeam = double(fieldOrLocal(Beam, 'MainBeam', [90 -90]));
mainBeam = mainBeam(:).';
if numel(mainBeam) ~= 2 || any(~isfinite(mainBeam)) || mainBeam(2) > mainBeam(1)
    error('GetBeamWeight:InvalidMainBeam', 'Beam.MainBeam must be [mainUpper, mainLower].');
end

sideRange = fieldOrLocal(Beam, 'SideRange', ...
    [mainBeam(2) mainBeam(2); mainBeam(1) mainBeam(1)]);
sideRange = double(sideRange);
if ~isequal(size(sideRange), [2 2]) || any(~isfinite(sideRange(:)))
    error('GetBeamWeight:InvalidSideRange', 'Beam.SideRange must be a finite 2-by-2 matrix.');
end
% Older App versions used this reversed matrix as a "disabled" sentinel.
% Migrate that exact legacy value only; all other invalid orderings still
% reach ValidateBeamRanges and raise a useful configuration error.
if isequal(sideRange, [90 90; -90 -90])
    sideRange = [mainBeam(2) mainBeam(2); mainBeam(1) mainBeam(1)];
end
ValidateBeamRanges(mainBeam, sideRange);

if isfield(Beam, 'ElevSideDown_dB') && ~isempty(Beam.ElevSideDown_dB)
    elevDownRaw = Beam.ElevSideDown_dB;
else
    elevDownRaw = fieldOrLocal(Beam, 'SideDown_dB', 0);
end
elevSideDownDb = normalizeDownDbLocal(elevDownRaw, ...
    'Beam.ElevSideDown_dB/SideDown_dB', '[lower upper]');

azRange = double(fieldOrLocal(Beam, 'AzimuthRange', [-180 180]));
azRange = azRange(:).';
if numel(azRange) ~= 2 || any(~isfinite(azRange))
    error('GetBeamWeight:InvalidAzimuthRange', ...
        'Beam.AzimuthRange must contain two finite values.');
end

azSideRange = fieldOrLocal(Beam, 'AzimuthSideRange', []);
if ~isempty(azSideRange)
    azSideRange = double(azSideRange);
    if ~isequal(size(azSideRange), [2 2]) || any(~isfinite(azSideRange(:)))
        error('GetBeamWeight:InvalidAzimuthSideRange', ...
            'Beam.AzimuthSideRange must be empty or a finite 2-by-2 matrix.');
    end
end
azSideDownDb = normalizeDownDbLocal( ...
    fieldOrLocal(Beam, 'AzimuthSideDown_dB', 0), ...
    'Beam.AzimuthSideDown_dB', '[left right]');
end

function value = normalizeDownDbLocal(value, fieldName, orderText)
value = double(value(:).');
if isscalar(value)
    value = [value value];
end
if numel(value) ~= 2 || any(~isfinite(value)) || any(value > 0)
    error('GetBeamWeight:InvalidSideDown', ...
        '%s must be a finite scalar <= 0 or a two-element %s vector.', ...
        fieldName, orderText);
end
end

function value = fieldOrLocal(S, name, defaultValue)
if isfield(S, name) && ~isempty(S.(name))
    value = S.(name);
else
    value = defaultValue;
end
end

function tf = isAzimuthInRangeLocal(phiDeg, rangeDeg)
if circularWidthLocal(rangeDeg) >= 359.999
    tf = true;
    return;
end
phi = WrapAzimuth180(phiDeg);
left = WrapAzimuth180(rangeDeg(1));
right = WrapAzimuth180(rangeDeg(2));
if left <= right
    tf = phi >= left-1e-9 && phi <= right+1e-9;
else
    tf = phi >= left-1e-9 || phi <= right+1e-9;
end
end

function width = circularWidthLocal(rangeDeg)
rangeDeg = double(rangeDeg(:).');
if abs(rangeDeg(2)-rangeDeg(1)) >= 359.999
    width = 360;
else
    width = mod(rangeDeg(2)-rangeDeg(1), 360);
end
end
