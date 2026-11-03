function [ArrayGeom, Validation] = BuildTowedArrayGeometry(InputParams, ArrayGeomIn)
% BuildTowedArrayGeometry  Build horizontal or rigid-tilt towed HLA geometry.
%
% Coordinates use the existing event-table convention:
%   x: range coordinate, y: cross-range coordinate, z: positive depth.
%
% GeometryMode:
%   horizontal : nominal horizontal HLA at CenterDepth/Rd.
%   rigid_tilt : rigid HLA with pitch angle PitchDeg and heading angle
%                ArrayHeadingDeg. Positive PitchDeg means element offset
%                s_m increases depth when s_m is positive.

    if nargin < 1 || isempty(InputParams)
        InputParams = struct();
    end
    if nargin < 2 || isempty(ArrayGeomIn)
        ArrayGeomIn = struct();
    end

    Towed = struct();
    if isstruct(InputParams) && isfield(InputParams, 'TowedArray') && isstruct(InputParams.TowedArray)
        Towed = InputParams.TowedArray;
    end

    N = getFirstFieldLocal(ArrayGeomIn, {'N','NumElements','NArray','ElementCount'}, []);
    if isempty(N)
        N = getFirstFieldLocal(Towed, {'N','NumElements','NArray','ElementCount'}, []);
    end
    if isempty(N)
        N = getFirstFieldLocal(InputParams, {'N','NumElements','NArray','ElementCount'}, 512);
    end
    N = max(1, round(double(N)));

    d = getFirstFieldLocal(ArrayGeomIn, {'d','D','ArraySpacing','ElementSpacing'}, []);
    if isempty(d)
        d = getFirstFieldLocal(Towed, {'d','D','ArraySpacing','ElementSpacing'}, []);
    end
    if isempty(d)
        d = getFirstFieldLocal(InputParams, {'d','D','ArraySpacing','ElementSpacing'}, 1.5);
    end
    d = double(d);

    centerX = getFirstFieldLocal(Towed, {'CenterX','RecvRange','ReferenceRange','CenterRange','Range'}, []);
    if isempty(centerX)
        centerX = getFirstFieldLocal(ArrayGeomIn, {'CenterX','RecvRange','ReferenceRange','CenterRange','Range'}, []);
    end
    if isempty(centerX)
        centerX = getFirstFieldLocal(InputParams, {'RecvRange','ReferenceRange','CenterRange','Range'}, NaN);
    end

    centerY = getFirstFieldLocal(Towed, {'CenterY'}, []);
    if isempty(centerY)
        centerY = getFirstFieldLocal(ArrayGeomIn, {'CenterY'}, 0);
    end

    centerZ = getFirstFieldLocal(Towed, {'CenterDepth','Rd','ReceiverDepth','ReferenceDepth'}, []);
    if isempty(centerZ)
        centerZ = getFirstFieldLocal(ArrayGeomIn, {'CenterDepth','Rd','ReceiverDepth','ReferenceDepth'}, []);
    end
    if isempty(centerZ)
        centerZ = getFirstFieldLocal(InputParams, {'Rd','ReceiverDepth','ReferenceDepth'}, NaN);
    end
    centerXYZ = double([centerX, centerY, centerZ]);

    headingDeg = getFirstFieldLocal(Towed, {'ArrayHeadingDeg','HeadingDeg','Heading'}, ...
        getFirstFieldLocal(ArrayGeomIn, {'ArrayHeadingDeg','HeadingDeg','Heading'}, 0));
    pitchDeg = getFirstFieldLocal(Towed, {'PitchDeg','Pitch'}, ...
        getFirstFieldLocal(ArrayGeomIn, {'PitchDeg','Pitch'}, 0));
    headingDeg = double(headingDeg);
    pitchDeg = double(pitchDeg);

    geometryMode = char(getFirstFieldLocal(Towed, {'GeometryMode'}, ...
        getFirstFieldLocal(ArrayGeomIn, {'GeometryMode'}, 'horizontal')));
    geometryMode = lower(strtrim(geometryMode));
    if strcmp(geometryMode, 'rigid') || strcmp(geometryMode, 'tilt')
        geometryMode = 'rigid_tilt';
    end
    if ~ismember(geometryMode, {'horizontal','rigid_tilt'})
        error('BuildTowedArrayGeometry:InvalidGeometryMode', ...
            'GeometryMode must be horizontal or rigid_tilt.');
    end

    refElement = getFirstFieldLocal(Towed, {'ReferenceElement','RefElement','CenterIndex','RefElementIndex'}, ...
        getFirstFieldLocal(ArrayGeomIn, {'ReferenceElement','RefElement','CenterIndex','RefElementIndex'}, (N + 1) / 2));
    refElement = double(refElement);
    s = ((1:N).' - refElement) * d;

    userXYZ = getFirstFieldLocal(Towed, {'ElementXYZ'}, []);
    if isempty(userXYZ)
        userXYZ = getFirstFieldLocal(ArrayGeomIn, {'ElementXYZ'}, []);
    end

    psi = deg2rad(headingDeg);
    gamma = deg2rad(pitchDeg);
    axisNominal = [cos(psi), sin(psi), 0];
    if strcmp(geometryMode, 'rigid_tilt')
        axisUnit = [cos(gamma) * cos(psi), cos(gamma) * sin(psi), sin(gamma)];
    else
        axisUnit = axisNominal;
        pitchDeg = 0;
    end

    nominalXYZ = bsxfun(@plus, centerXYZ, s * axisNominal);
    if ~isempty(userXYZ)
        elementXYZ = double(userXYZ);
        if size(elementXYZ, 2) ~= 3 && size(elementXYZ, 1) == 3
            elementXYZ = elementXYZ.';
        end
        if size(elementXYZ, 2) ~= 3
            error('BuildTowedArrayGeometry:InvalidElementXYZ', ...
                'ElementXYZ must be an N-by-3 matrix.');
        end
        N = size(elementXYZ, 1);
        % 对偶数阵元阵列，ReferenceElement=(N+1)/2 是半整数，几何
        % 中心位于中间两个阵元之间，不能 round 后吸附到某个实体阵元。
        % 只有调用方没有给出有效中心时，才由全部阵元的质心恢复中心。
        if any(~isfinite(centerXYZ)) && all(isfinite(elementXYZ(:)))
            centerXYZ = mean(elementXYZ, 1);
        end
        source = 'provided';
    else
        elementXYZ = bsxfun(@plus, centerXYZ, s * axisUnit);
        source = 'built';
    end

    if N > 1
        spacings = sqrt(sum(diff(elementXYZ, 1, 1).^2, 2));
        finiteSpacing = spacings(isfinite(spacings));
        if ~isempty(finiteSpacing)
            d = median(finiteSpacing);
        end
    end

    ArrayGeom = ArrayGeomIn;
    ArrayGeom.N = N;
    ArrayGeom.NumElements = N;
    ArrayGeom.NArray = N;
    ArrayGeom.d = d;
    ArrayGeom.ArraySpacing = d;
    ArrayGeom.ElementSpacing = d;
    ArrayGeom.CenterXYZ = centerXYZ;
    ArrayGeom.CenterX = centerXYZ(1);
    ArrayGeom.CenterY = centerXYZ(2);
    ArrayGeom.CenterDepth = centerXYZ(3);
    ArrayGeom.RecvRange = centerXYZ(1);
    ArrayGeom.Rd = centerXYZ(3);
    ArrayGeom.ElementXYZ = elementXYZ;
    ArrayGeom.NominalElementXYZ = nominalXYZ;
    ArrayGeom.ElementX = elementXYZ(:, 1) - centerXYZ(1);
    ArrayGeom.NominalElementX = nominalXYZ(:, 1) - centerXYZ(1);
    ArrayGeom.AxisUnit = axisUnit ./ max(norm(axisUnit), eps);
    ArrayGeom.NominalAxisUnit = axisNominal ./ max(norm(axisNominal), eps);
    ArrayGeom.ArrayHeadingDeg = headingDeg;
    ArrayGeom.PitchDeg = pitchDeg;
    ArrayGeom.PitchSource = char(getFirstFieldLocal(Towed, {'PitchSource'}, 'manual'));
    ArrayGeom.GeometryMode = geometryMode;
    ArrayGeom.ReferenceElement = refElement;
    ArrayGeom.ElementXYZSource = source;

    Validation = ValidateTowedArrayGeometry(ArrayGeom);
end

function val = getFirstFieldLocal(S, names, defaultVal)
    val = defaultVal;
    if ~isstruct(S)
        return;
    end
    for kk = 1:numel(names)
        name = names{kk};
        if isfield(S, name) && ~isempty(S.(name))
            val = S.(name);
            return;
        end
    end
end
