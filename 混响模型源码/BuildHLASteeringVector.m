function [W, Info] = BuildHLASteeringVector(ArrayGeom, scanAngles, k, steeringMode)
% BuildHLASteeringVector  Build HLA beam weights for BTR synthesis.
%
% scanAngles use the project convention:
%   0 deg = broadside, +/-90 deg = endfire.
%
% steeringMode:
%   nominal_horizontal : use NominalElementXYZ, i.e. pitch-compensation off.
%   geometry_matched   : use actual ElementXYZ, i.e. pitch-compensation on.

    if nargin < 4 || isempty(steeringMode)
        steeringMode = 'nominal_horizontal';
    end
    steeringMode = parseSteeringModeLocal(steeringMode);
    scanAngles = double(scanAngles(:));
    k = double(k);

    if strcmpi(steeringMode, 'geometry_matched')
        elementXYZ = getFieldLocal(ArrayGeom, 'ElementXYZ', []);
        source = 'ElementXYZ';
    else
        elementXYZ = getFieldLocal(ArrayGeom, 'NominalElementXYZ', []);
        source = 'NominalElementXYZ';
        if isempty(elementXYZ)
            elementXYZ = getFieldLocal(ArrayGeom, 'ElementXYZ', []);
            source = 'ElementXYZ_fallback';
        end
    end
    if isempty(elementXYZ)
        xElem = getFieldLocal(ArrayGeom, 'ElementX', []);
        if isempty(xElem)
            N = getFieldLocal(ArrayGeom, 'N', 1);
            d = getFieldLocal(ArrayGeom, 'd', 0);
            xElem = ((1:N).' - (N + 1) / 2) * d;
        end
        centerXYZ = getCenterXYZLocal(ArrayGeom);
        elementXYZ = [centerXYZ(1) + double(xElem(:)), zeros(numel(xElem), 1) + centerXYZ(2), ...
            zeros(numel(xElem), 1) + centerXYZ(3)];
        source = 'ElementX_fallback';
    end
    elementXYZ = double(elementXYZ);
    centerXYZ = getCenterXYZLocal(ArrayGeom);
    offsetXYZ = bsxfun(@minus, elementXYZ, centerXYZ);

    headingDeg = getFieldLocal(ArrayGeom, 'ArrayHeadingDeg', 0);
    psi = deg2rad(double(headingDeg));
    a0 = [cos(psi), sin(psi), 0];
    b0 = [-sin(psi), cos(psi), 0];

    nScan = numel(scanAngles);
    U = zeros(3, nScan);
    for ii = 1:nScan
        theta = deg2rad(scanAngles(ii));
        U(:, ii) = (cos(theta) * b0 + sin(theta) * a0).';
    end

    % Negative sign preserves the existing BTR convention where positive
    % endfire peaks at positive scan angle for events from +array axis.
    phase = offsetXYZ * U;
    W = exp(-1i * k * phase);

    Info = struct();
    Info.SteeringMode = steeringMode;
    Info.GeometrySource = source;
    Info.ArrayHeadingDeg = headingDeg;
    Info.ScanAngleConvention = '0deg_broadside_90deg_endfire';
end

function mode = parseSteeringModeLocal(rawMode)
    if isstring(rawMode)
        rawMode = char(rawMode(1));
    end
    mode = lower(strtrim(char(rawMode)));
    switch mode
        case {'nominal_horizontal','nominal','horizontal','legacy'}
            mode = 'nominal_horizontal';
        case {'geometry_matched','matched','actual','rigid_tilt'}
            mode = 'geometry_matched';
        otherwise
            error('BuildHLASteeringVector:InvalidSteeringMode', ...
                'SteeringMode must be nominal_horizontal or geometry_matched.');
    end
end

function centerXYZ = getCenterXYZLocal(ArrayGeom)
    centerXYZ = getFieldLocal(ArrayGeom, 'CenterXYZ', []);
    if isempty(centerXYZ)
        centerXYZ = [getFieldLocal(ArrayGeom, 'RecvRange', 0), ...
            getFieldLocal(ArrayGeom, 'CenterY', 0), ...
            getFieldLocal(ArrayGeom, 'Rd', 0)];
    end
    centerXYZ = double(centerXYZ(:).');
end

function val = getFieldLocal(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        val = S.(fieldName);
    else
        val = defaultVal;
    end
end
