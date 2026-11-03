function Report = ValidateTowedArrayGeometry(ArrayGeom, tol)
% ValidateTowedArrayGeometry  Validate ElementXYZ consistency for a towed HLA.

    if nargin < 2 || isempty(tol)
        tol = 1e-6;
    end

    Report = struct();
    Report.Pass = true;
    Report.Messages = {};
    Report.MaxSpacingError = NaN;
    Report.MaxAxisResidual = NaN;
    Report.MaxPitch0ZError = NaN;
    Report.NumTiltedElements = 0;

    if nargin < 1 || ~isstruct(ArrayGeom) || ~isfield(ArrayGeom, 'ElementXYZ') || isempty(ArrayGeom.ElementXYZ)
        Report = addFail(Report, 'missing ElementXYZ');
        return;
    end

    xyz = double(ArrayGeom.ElementXYZ);
    if size(xyz, 2) ~= 3
        Report = addFail(Report, 'ElementXYZ must be N-by-3');
        return;
    end
    if any(~isfinite(xyz(:)))
        Report = addFail(Report, 'ElementXYZ contains non-finite values');
        return;
    end

    N = getFieldLocal(ArrayGeom, 'N', size(xyz, 1));
    if round(double(N)) ~= size(xyz, 1)
        Report = addFail(Report, 'N does not match ElementXYZ rows');
    end

    d = getFieldLocal(ArrayGeom, 'd', NaN);
    if size(xyz, 1) > 1 && isfinite(d) && d > 0
        spacing = sqrt(sum(diff(xyz, 1, 1).^2, 2));
        Report.MaxSpacingError = max(abs(spacing - d));
        if Report.MaxSpacingError > max(tol, 1e-6 * d)
            Report = addFail(Report, 'adjacent element spacing differs from d');
        end
    end

    centerXYZ = getFieldLocal(ArrayGeom, 'CenterXYZ', []);
    if isempty(centerXYZ)
        centerXYZ = [getFieldLocal(ArrayGeom, 'RecvRange', NaN), 0, getFieldLocal(ArrayGeom, 'Rd', NaN)];
    end
    centerXYZ = double(centerXYZ(:).');
    axisUnit = getFieldLocal(ArrayGeom, 'AxisUnit', []);
    if ~isempty(axisUnit) && numel(axisUnit) == 3 && all(isfinite(centerXYZ))
        axisUnit = double(axisUnit(:).');
        axisUnit = axisUnit ./ max(norm(axisUnit), eps);
        rel = bsxfun(@minus, xyz, centerXYZ);
        crossNorm = sqrt(sum(cross(rel, repmat(axisUnit, size(rel, 1), 1), 2).^2, 2));
        Report.MaxAxisResidual = max(crossNorm);
        if Report.MaxAxisResidual > max(tol, 1e-6 * max(1, max(abs(rel(:)))))
            Report = addFail(Report, 'elements are not collinear with AxisUnit');
        end
    end

    rd = getFieldLocal(ArrayGeom, 'Rd', getFieldLocal(ArrayGeom, 'CenterDepth', NaN));
    pitchDeg = getFieldLocal(ArrayGeom, 'PitchDeg', NaN);
    if isfinite(rd) && isfinite(pitchDeg)
        zErr = abs(xyz(:, 3) - rd);
        Report.NumTiltedElements = sum(zErr > max(tol, 1e-6));
        if abs(pitchDeg) <= max(tol, 1e-9)
            Report.MaxPitch0ZError = max(zErr);
            if Report.MaxPitch0ZError > max(tol, 1e-6)
                Report = addFail(Report, 'PitchDeg=0 but element depths are not constant');
            end
        end
    end
end

function Report = addFail(Report, msg)
    Report.Pass = false;
    Report.Messages{end+1, 1} = msg;
end

function val = getFieldLocal(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        val = S.(fieldName);
    else
        val = defaultVal;
    end
end
