function resolved = ResolveScatteringPreset(cfg)
%ResolveScatteringPreset Resolve dB scattering coefficient and slope radians.
if ~isstruct(cfg), error('ResolveScatteringPreset:InvalidInput', 'Scattering must be a struct.'); end
miuMode = lower(string(fieldOrLocal(cfg,'miuMode','manual')));
switch miuMode
    case "manual", miu = requiredScalarLocal(cfg,'miu');
    case "smooth", miu = -33;
    case "low_roughness", miu = -32;
    case "low_to_medium_roughness", miu = -31;
    case "medium_roughness", miu = -30;
    case "medium_to_high_roughness", miu = -29;
    case "high_roughness", miu = -28;
    case "very_high_roughness", miu = -27;
    otherwise, error('ResolveScatteringPreset:UnknownMiuMode', 'Unknown Scattering.miuMode: %s', miuMode);
end
slopeMode = lower(string(fieldOrLocal(cfg,'bottomSlopeMode','manual')));
switch slopeMode
    case "manual"
        if isfield(cfg,'bottomRmsSlopeRad') && ~isempty(cfg.bottomRmsSlopeRad)
            slopeRad = requiredScalarLocal(cfg,'bottomRmsSlopeRad');
        else
            % 兼容旧版JSON；新配置应使用bottomRmsSlopeRad消除单位歧义。
            slopeRad = deg2rad(requiredScalarLocal(cfg,'bottomRmsSlopeDeg'));
        end
    case "flat", slopeRad = deg2rad(8);
    case "very_gentle_slope", slopeRad = deg2rad(9);
    case "gentle_slope", slopeRad = deg2rad(10);
    case "steep_slope", slopeRad = deg2rad(11);
    otherwise, error('ResolveScatteringPreset:UnknownSlopeMode', 'Unknown Scattering.bottomSlopeMode: %s', slopeMode);
end
roughnessDb = double(fieldOrLocal(cfg,'roughnessDb',-10));
validateattributes([miu slopeRad roughnessDb], {'numeric'}, {'real','finite'});
if slopeRad < 0 || slopeRad >= pi/2
    error('ResolveScatteringPreset:InvalidSlope', ...
        'Bottom RMS slope must be in [0, pi/2) rad.');
end
resolved = struct('miuMode',char(miuMode),'miuDb',miu, ...
    'bottomSlopeMode',char(slopeMode),'bottomRmsSlopeRad',slopeRad, ...
    'bottomRmsSlopeDeg',rad2deg(slopeRad), ...
    'roughnessDb',roughnessDb);
end

function value = fieldOrLocal(S,name,defaultValue)
if isfield(S,name) && ~isempty(S.(name)), value=S.(name); else, value=defaultValue; end
end
function value = requiredScalarLocal(S,name)
if ~isfield(S,name), error('ResolveScatteringPreset:MissingField','Missing Scattering.%s.',name); end
value=double(S.(name)); validateattributes(value,{'numeric'},{'scalar','real','finite'});
end
