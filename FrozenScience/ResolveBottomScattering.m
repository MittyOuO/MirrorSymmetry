function [S, Audit] = ResolveBottomScattering(InputParams, consumerProfile)
%ResolveBottomScattering Resolve explicit bottom-scattering units once.
% Canonical mode never guesses units. Legacy mode exists only to reproduce
% TH01-01-v1 behavior and is never paper eligible.

if nargin < 2 || isempty(consumerProfile)
    consumerProfile = 'event';
end
consumerProfile = lower(strtrim(char(string(consumerProfile))));

convention = 'legacy';
if isstruct(InputParams) && isfield(InputParams,'Scattering') && ...
        isstruct(InputParams.Scattering) && isfield(InputParams.Scattering,'Bottom') && ...
        isstruct(InputParams.Scattering.Bottom) && ...
        isfield(InputParams.Scattering.Bottom,'InputConvention') && ...
        ~isempty(InputParams.Scattering.Bottom.InputConvention)
    convention = lower(strtrim(char(string( ...
        InputParams.Scattering.Bottom.InputConvention))));
end

switch convention
    case 'canonical'
        B = InputParams.Scattering.Bottom;
        required = {'ThtDeg','ThtRad','MiuDb','MiuLinear','vLinear'};
        for k = 1:numel(required)
            if ~isfield(B,required{k}) || isempty(B.(required{k}))
                error('G3:MissingCanonicalScatteringField', ...
                    'Canonical scattering requires InputParams.Scattering.Bottom.%s.',required{k});
            end
        end
        thtDeg = scalarFiniteLocal(B.ThtDeg,'ThtDeg');
        thtRad = scalarFiniteLocal(B.ThtRad,'ThtRad');
        miuDb = scalarFiniteLocal(B.MiuDb,'MiuDb');
        miuLinear = scalarFiniteLocal(B.MiuLinear,'MiuLinear');
        vLinear = scalarFiniteLocal(B.vLinear,'vLinear');
        expectedTht = deg2rad(thtDeg);
        expectedMiu = 10.^(miuDb/10);
        assertCloseLocal(thtRad,expectedTht,'ThtRad','deg2rad(ThtDeg)');
        assertCloseLocal(miuLinear,expectedMiu,'MiuLinear','10^(MiuDb/10)');
        if thtRad <= 0 || miuLinear <= 0 || vLinear <= 0
            error('G3:InvalidCanonicalScatteringValue', ...
                'Canonical ThtRad, MiuLinear and vLinear must be positive.');
        end
        paperEligible = true;
        legacyProfile = '';

    case 'legacy'
        thtRaw = fieldOrLocal(InputParams,'Tht',9);
        miuRaw = fieldOrLocal(InputParams,'Miu',-32);
        vRaw = fieldOrLocal(InputParams,'v',-10);
        thtRaw = scalarFiniteLocal(thtRaw,'legacy Tht');
        miuRaw = scalarFiniteLocal(miuRaw,'legacy Miu');
        vRaw = scalarFiniteLocal(vRaw,'legacy v');
        switch consumerProfile
            case {'event','single','channels'}
                thtRad = deg2rad(thtRaw);
                miuLinear = 10.^(miuRaw/10);
                vLinear = 10.^(vRaw/10);
                legacyProfile = 'event';
            case {'fast_rl','fastrl'}
                thtRad = thtRaw;
                if abs(thtRad) > pi, thtRad = deg2rad(thtRad); end
                if miuRaw <= 0, miuLinear = 10.^(miuRaw/10); else, miuLinear = miuRaw; end
                if vRaw <= 0, vLinear = 10.^(vRaw/10); else, vLinear = vRaw; end
                legacyProfile = 'fast_rl';
            otherwise
                error('G3:UnknownLegacyConsumerProfile', ...
                    'Unknown legacy scattering consumer profile: %s.',consumerProfile);
        end
        thtDeg = thtRaw;
        miuDb = miuRaw;
        paperEligible = false;

    otherwise
        error('G3:UnknownScatteringConvention', ...
            'InputConvention must be legacy or canonical, not %s.',convention);
end

S = struct('InputConvention',convention,'PaperEligible',paperEligible, ...
    'ThtDeg',thtDeg,'ThtRad',thtRad,'MiuDb',miuDb, ...
    'MiuLinear',miuLinear,'vLinear',vLinear, ...
    'LegacyConsumerProfile',legacyProfile);
Audit = S;
Audit.ConversionBoundary = mfilename;
Audit.NoDownstreamConversionAllowed = true;
end

function value = scalarFiniteLocal(value,name)
value = double(value);
if ~isscalar(value) || ~isreal(value) || ~isfinite(value)
    error('G3:InvalidScatteringValue','%s must be a finite real scalar.',name);
end
end

function assertCloseLocal(actual,expected,actualName,expectedName)
tol = 32*eps(max([1,abs(actual),abs(expected)]));
if abs(actual-expected) > tol
    error('G3:InconsistentCanonicalScattering', ...
        '%s=%.17g is inconsistent with %s=%.17g (tol %.3g).', ...
        actualName,actual,expectedName,expected,tol);
end
end

function value = fieldOrLocal(S,name,defaultValue)
if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
    value = S.(name);
else
    value = defaultValue;
end
end
