function [SSPFinal, AxisInfo] = AdjustSSPToWaterDepth(rawSSP, waterDepth, varargin)
%AdjustSSPToWaterDepth Truncate or continuously extend SSP to the seabed.
validateattributes(waterDepth, {'numeric'}, {'scalar','real','finite','positive'});
SSP = ValidateAndFormatSSP(rawSSP);
z = SSP(:,1); c = SSP(:,2);
[cMin, idx] = min(c);
zAxis = z(idx);
useCanonicalAxis = nargin >= 3 && logical(varargin{1});
if useCanonicalAxis
    zAxisForExtension = 1300;
    detectionRule = 'canonical_munk_axis_1300m';
else
    zAxisForExtension = zAxis;
    detectionRule = 'global_sample_minimum';
end
willExtend = waterDepth > z(end) + 1e-9;
AxisInfo = struct( ...
    'DetectionRule',detectionRule, ...
    'Index',idx, ...
    'Depth',zAxis, ...
    'SoundSpeed',cMin, ...
    'IsBoundary',idx==1 || idx==numel(z), ...
    'IsSurfaceBoundary',idx==1, ...
    'IsDeepBoundary',idx==numel(z), ...
    'AxisDepthUsedForExtension',zAxisForExtension, ...
    'UsedForExtension',logical(willExtend));
if waterDepth <= z(end) + 1e-9
    keep = z < waterDepth;
    cBottom = interp1(z,c,waterDepth,'pchip');
    SSPFinal = [z(keep),c(keep); waterDepth,cBottom];
else
    nTail = min(5, numel(z));
    dz = median(diff(z(end-nTail+1:end)));
    if ~isfinite(dz) || dz <= 0, dz = 50; end
    dz = min(max(dz,25),100);
    zExt = (z(end)+dz:dz:waterDepth).';
    if isempty(zExt) || abs(zExt(end)-waterDepth) > 1e-9, zExt(end+1,1) = waterDepth; end
    cExt = c(end) + MunkCanonicalSoundSpeed(zExt,zAxisForExtension) ...
        - MunkCanonicalSoundSpeed(z(end),zAxisForExtension);
    SSPFinal = [SSP; zExt,cExt];
end
SSPFinal = ValidateAndFormatSSP(SSPFinal);
if abs(SSPFinal(end,1)-waterDepth) > 1e-9
    error('AdjustSSPToWaterDepth:Internal', 'Final SSP does not end at waterDepth.');
end
end
