function [OpenAngle, Audit] = ResolveBeamOpenAngle(Beam)
%ResolveBeamOpenAngle Resolve the BELLHOP source-leg elevation envelope.
%   OpenAngle is always returned in the project convention [upper lower].
%   For an automatic V2 elevation model it is the continuous hull of
%   Main.SupportRangeDeg and every SecondaryLobes.SupportRangeDeg. Residual
%   ranges, including manual overrides, never enlarge this envelope.
%   Legacy/custom beams fall back to MainBeam.

if nargin < 1 || ~isstruct(Beam) || ~isscalar(Beam)
    error('ResolveBeamOpenAngle:InvalidBeam', ...
        'Beam must be a scalar structure.');
end

mainBeam = readRangeLocal(Beam,'MainBeam',true);
rangeList = mainBeam;
source = 'legacy_or_custom_mainbeam';
secondarySupports = zeros(0,2);
usedV2 = false;

hasV2 = isfield(Beam,'WeightModelVersion') && ...
    isnumeric(Beam.WeightModelVersion) && isscalar(Beam.WeightModelVersion) && ...
    isfinite(Beam.WeightModelVersion) && double(Beam.WeightModelVersion) >= 2;
hasElevationModel = isfield(Beam,'ElevationWeightModel') && ...
    isstruct(Beam.ElevationWeightModel) && ...
    isscalar(Beam.ElevationWeightModel) && ...
    ~isempty(fieldnames(Beam.ElevationWeightModel));

if hasV2 && hasElevationModel
    M = Beam.ElevationWeightModel;
    if ~isfield(M,'Main') || ~isstruct(M.Main) || ...
            ~isfield(M.Main,'SupportRangeDeg')
        error('ResolveBeamOpenAngle:MissingMainSupport', ...
            'V2 elevation model is missing Main.SupportRangeDeg.');
    end
    mainSupport = readRangeLocal(M.Main,'SupportRangeDeg',true);
    rangeList = mainSupport;
    if isfield(M,'SecondaryLobes') && ~isempty(M.SecondaryLobes)
        L = M.SecondaryLobes;
        secondarySupports = zeros(numel(L),2);
        for k = 1:numel(L)
            secondarySupports(k,:) = readRangeLocal( ...
                L(k),'SupportRangeDeg',true);
        end
        rangeList = [rangeList;secondarySupports]; %#ok<AGROW>
    end
    source = 'v2_main_secondary_support_hull';
    usedV2 = true;
end

allValues = double(rangeList(:));
OpenAngle = [max(allValues),min(allValues)];
OpenAngle = max(min(OpenAngle,90),-90);
if OpenAngle(1) < OpenAngle(2)
    error('ResolveBeamOpenAngle:InvalidResolvedOrder', ...
        'Resolved OpenAngle must use [upper lower] ordering.');
end

Audit = struct();
Audit.Policy = 'main_secondary_support_hull_residual_excluded';
Audit.Source = source;
Audit.UsedV2ElevationModel = usedV2;
Audit.MainBeam3dB = mainBeam;
if usedV2
    Audit.MainSupportRangeDeg = rangeList(1,:);
else
    Audit.MainSupportRangeDeg = mainBeam;
end
Audit.SecondarySupports = secondarySupports;
Audit.ResidualExpandedOpenAngle = false;
Audit.OpenAngle = OpenAngle;
end

function r = readRangeLocal(S,name,clampElevation)
if ~isfield(S,name) || isempty(S.(name))
    error('ResolveBeamOpenAngle:MissingRange', ...
        'Required beam range is missing: %s.',name);
end
r = double(S.(name)(:).');
if numel(r) ~= 2 || any(~isfinite(r))
    error('ResolveBeamOpenAngle:InvalidRange', ...
        '%s must contain two finite values.',name);
end
if clampElevation && any(r < -90-1e-9 | r > 90+1e-9)
    error('ResolveBeamOpenAngle:RangeOutOfBounds', ...
        '%s must remain within [-90,90] degrees.',name);
end
r = [min(r),max(r)];
end
