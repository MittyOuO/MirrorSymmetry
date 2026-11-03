function [BeamEq, elemPos, figH] = ConfigureArrayBeam(Beam, varargin)
% ConfigureArrayBeam
% 体积阵/阵列配置到混响模型等效束控参数的转换函数。
%
% 核心思想：
%   二维主切面 -3 dB 交点与三维主瓣连通区投影是两个不同概念：
%       1) Pattern2D / PrincipalCuts 保存主切面插值交点；
%       2) Projection3D 保存三维连通区的离散投影，仅用于诊断/审计。
%   模型等效角域按阵型使用对应主切面的 HPBW；没有对应方向孔径时，
%   保持产品约定的全向范围。
%
% 输入：
%   Beam.arrayType  : 阵型选择
%       1 或 'vertical'             = 垂直线列阵
%       2 或 'linear' / 'horizontal'= 水平线列阵
%       3 或 'cylindrical'          = 圆柱阵
%       4 或 'cylindrical_vertical' = 圆柱阵垂直
%       5 或 'custom'               = 用户直接输入等效束控范围
%
%   Beam.centerDepth : 阵列几何中心深度，单位 m。若缺省，默认为 0。
%
%   Beam.azimuthSearchRangeDeg : 三维主瓣投影时允许搜索的水平方位范围，单位 deg。
%                                缺省为 Beam.azimuthRangeDefaultDeg 或 [-180 180]。
%                                统一口径：水平全向为 [-180 180]；
%                                俯仰全向为 [90 -90]（上下界写法）。
%
%   Beam.verticalArray / Beam.horiArray / Beam.cylinArray : 对应阵型参数结构体。
%
%   自定义等效配置可使用：
%       Beam.openAngleRangeDeg / Beam.elevRangeDeg / Beam.OpenAngleRangeDeg
%       Beam.azimuthRangeDeg   / Beam.azRangeDeg   / Beam.AzimuthRangeDeg
%
% 输出：
%   BeamEq.Sd                    : 等效声源深度，单位 m。
%   BeamEq.OpenAngleRangeDeg     : 几何俯仰方向束控范围 [upper lower]，单位 deg。
%                                  注意：这里保留几何俯仰角方向；若后续写入
%                                  BELLHOP/混响模型且模型采用"正值向下"，需先做
%                                  thetaModel = -thetaGeom。
%   BeamEq.AzimuthRangeDeg       : 水平方向束控范围 [azLeft azRight]，单位 deg。
%                                  以 x 正半轴为 0°，逆时针为正，范围 [-180,180]。
%                                  用于散射面元 phiS = atan2d(y,x) 的方位筛选。
%   BeamEq.OpenAngleDeg          : 几何俯仰方向 -3 dB 等效全开角，单位 deg。
%   BeamEq.AzimuthOpenAngleDeg   : 水平方位方向 -3 dB 等效全开角，单位 deg。
%   BeamEq.ElevationDeg          : 由俯仰范围反算得到的轴向几何俯仰角，单位 deg。
%   BeamEq.AzimuthDeg            : 由方位范围反算得到的轴向方位角，单位 deg。
%                                  主要用于兼容旧版 GetBeamWeight，不建议在 UI 单独展示。
%   BeamEq.Pattern2D             : UI 二维主切面显示数据。
%   BeamEq.Pattern3D             : UI 三维波束显示数据。
%   BeamEq.Projection3D          : 三维 -3 dB 主瓣区域投影结果。
%   elemPos                      : 阵元三维坐标 [x y z]，单位 m。
%   figH                         : 示意图句柄；若 Plot=false，则为空。

    p = inputParser;
    p.addParameter('Plot', true, @(x)islogical(x) || isnumeric(x));
    p.addParameter('ScanStepDeg', 0.05, @(x)isnumeric(x) && isscalar(x) && x > 0);      % 二维切面步长
    p.addParameter('Scan3DStepDeg', 1.0, @(x)isnumeric(x) && isscalar(x) && x > 0);     % 三维投影步长
    p.addParameter('ScanHalfWidthDeg', 89, @(x)isnumeric(x) && isscalar(x) && x > 0);
    p.parse(varargin{:});

    doPlot = logical(p.Results.Plot);
    scanStep = p.Results.ScanStepDeg;
    scan3DStep = p.Results.Scan3DStepDeg;
    scanHalfWidth = p.Results.ScanHalfWidthDeg;

    if ~isstruct(Beam)
        error('Beam 必须为结构体。');
    end

    arrayType = parseArrayType(getFieldLocal(Beam, 'arrayType', 1));
    centerDepth = getFieldLocal(Beam, 'centerDepth', 0);

    defaultAzRange = getFirstExistingField(Beam, ...
        {'azimuthRangeDefaultDeg','defaultAzimuthRangeDeg','azRangeDefaultDeg'}, [-180 180]);
    defaultAzRange = normalizeAngleRange(defaultAzRange, 'defaultAzRange');

    azSearchRange = getFirstExistingField(Beam, ...
        {'azimuthSearchRangeDeg','AzimuthSearchRangeDeg','azSearchRangeDeg'}, defaultAzRange);
    azSearchRange = normalizeAngleRange(azSearchRange, 'azimuthSearchRangeDeg');

    figH = [];
    notes = strings(0);
    Pattern2D = [];
    AzimuthPattern2D = [];

    % 以下变量在非 custom 阵型中赋值
    elemPos = [];
    fBeam = NaN;
    c = 1500;
    steerPhi = 0;
    steerTheta = 0;

    switch arrayType
        case 'custom'
            % 用户直接给等效参数，不计算阵因子。
            elevRange = getFirstExistingField(Beam, ...
                {'openAngleRangeDeg','OpenAngleRangeDeg','elevRangeDeg','ElevationRangeDeg'}, []);
            if isempty(elevRange)
                openAngle = getFieldLocal(Beam, 'openAngle', 180);
                elevation = getFieldLocal(Beam, 'thetaDeg', 0);
                elevRange = [elevation + openAngle/2, elevation - openAngle/2];
            end
            elevRange = normalizeElevRange(elevRange, 'custom.elevRange');

            azRange = getFirstExistingField(Beam, ...
                {'azimuthRangeDeg','AzimuthRangeDeg','azRangeDeg','AzRangeDeg'}, []);
            if isempty(azRange)
                azimuth = getFieldLocal(Beam, 'azimuthDeg', 0);
                azHalf = getFirstExistingField(Beam, {'azimuthOpenAngle','AzimuthOpenAngle'}, 180);
                azRange = rangeFromCenterWidth(azimuth, 2*azHalf);
            end
            azRange = normalizeAngleRange(azRange, 'custom.azRange');

            fBeam = getFirstExistingField(Beam, {'fBeam','fCenter'}, NaN);
            BeamEq = makeBeamEqFull(centerDepth, elevRange, azRange, fBeam, arrayType, ...
                '自定义等效束控参数：未进行阵因子计算。');
            BeamEq.Pattern2D = [];
            BeamEq.Pattern3D = [];
            BeamEq.Projection3D = [];
            BeamEq.WeightModelVersion = 1;
            BeamEq.ElevationWeightModel = [];
            BeamEq.AzimuthWeightModel = [];
            elemPos = zeros(0, 3);
            return;

        case 'vertical'
            A = getRequiredStruct(Beam, 'verticalArray');
            M = getFieldLocal(A, 'M', []);
            D = getFieldLocal(A, 'D', []);
            fLow = getFieldLocal(A, 'fLow', []);
            fUp = getFieldLocal(A, 'fUp', []);
            c = getFieldLocal(A, 'c', 1500);
            theta0 = getFieldLocal(A, 'thetaDeg', 0);
            tilt = getFieldLocal(A, 'tiltDeg', 0);
            validatePositiveScalar(M, 'verticalArray.M');
            validatePositiveScalar(D, 'verticalArray.D');
            fBeamUser = getFirstExistingField(A, {'fBeam','fCenter'}, []);
            fBeam = chooseBeamFrequency(fLow, fUp, fBeamUser, 'verticalArray');

            z = ((0:M-1) - (M-1)/2).' * D;
            elemPos = [zeros(M,1), zeros(M,1), z];
            elemPos = rotateY(elemPos, tilt);

            steerPhi = 0;
            steerTheta = theta0;

            scanAngles = makeElevationScan(theta0, scanStep);
            AF = arrayFactor(elemPos, fBeam, c, steerPhi, steerTheta, zeros(size(scanAngles)), scanAngles);
            [~, leftEl, rightEl, cutAudit] = halfPowerWidthAndBounds( ...
                scanAngles, abs(AF), theta0, 'bounded', [-90 90]);
            cutAudit.EffectiveRangeDeg = [leftEl, rightEl];
            Pattern2D = makePattern2D(scanAngles, abs(AF), leftEl, rightEl, theta0, ...
                'elevation', '俯仰角 (°)');
            Pattern2D.HPBWAudit = cutAudit;
            elevRangeCut = [rightEl, leftEl];
            azRangeCut = [-180, 180];
            notes(end+1) = '垂直线列阵：俯仰范围使用 elevation 主切面插值 HPBW，水平方位按产品规则保持全向 [-180,180]。';

        case 'linear'
            A = getRequiredStruct(Beam, 'horiArray');
            M = getFieldLocal(A, 'M', []);
            D = getFieldLocal(A, 'D', []);
            fLow = getFieldLocal(A, 'fLow', []);
            fUp = getFieldLocal(A, 'fUp', []);
            c = getFieldLocal(A, 'c', 1500);
            phi0 = getFieldLocal(A, 'phiDeg', 0);
            tilt = getFieldLocal(A, 'tiltDeg', 0);
            validatePositiveScalar(M, 'horiArray.M');
            validatePositiveScalar(D, 'horiArray.D');
            fBeamUser = getFirstExistingField(A, {'fBeam','fCenter'}, []);
            fBeam = chooseBeamFrequency(fLow, fUp, fBeamUser, 'horiArray');

            x = ((0:M-1) - (M-1)/2).' * D;
            elemPos = [x, zeros(M,1), zeros(M,1)];
            elemPos = rotateZ(elemPos, tilt);

            steerPhi = phi0;
            steerTheta = 0;

            [scanAngles, scanPhi] = makeCenteredAzimuthCut(phi0, 180, scanStep);
            AF = arrayFactor(elemPos, fBeam, c, steerPhi, steerTheta, scanPhi, zeros(size(scanPhi)));
            [~, leftAz, rightAz, cutAudit] = halfPowerWidthAndBounds( ...
                scanAngles, abs(AF), phi0, 'circular', []);
            Pattern2D = makePattern2D(scanAngles, abs(AF), leftAz, rightAz, phi0, ...
                'azimuth', '方位角 (°)');
            Pattern2D.HPBWAudit = cutAudit;
            if cutAudit.IsFullAzimuth
                Pattern2D.Wrapped3dBRangeDeg = [-180, 180];
            else
                Pattern2D.Wrapped3dBRangeDeg = localWrapTo180([leftAz, rightAz]);
            end
            cutAudit.EffectiveRangeDeg = Pattern2D.Wrapped3dBRangeDeg;
            Pattern2D.HPBWAudit = cutAudit;
            Pattern2D.AngleConvention = 'continuous unwrapped azimuth around steer angle';
            elevRangeCut = [90, -90];
            azRangeCut = Pattern2D.Wrapped3dBRangeDeg;
            notes(end+1) = '水平线列阵：方位范围使用 azimuth 主切面插值 HPBW，俯仰按产品规则保持全向 [90,-90]。';

        case {'cylindrical','cylindrical_vertical'}
            A = getRequiredStruct(Beam, 'cylinArray');
            M = getFieldLocal(A, 'M', []);
            m = getFieldLocal(A, 'm', []);
            r = getFieldLocal(A, 'r', []);
            H = getFieldLocal(A, 'H', []);
            fLow = getFirstExistingField(A, {'fLower','fLow'}, []);
            fUp = getFirstExistingField(A, {'fUpper','fUp'}, []);
            c = getFieldLocal(A, 'c', 1500);
            phi0 = getFieldLocal(A, 'phiDeg', 0);
            theta0 = getFieldLocal(A, 'thetaDeg', 0);
            tilt = getFieldLocal(A, 'tiltDeg', 0);
            validatePositiveScalar(M, 'cylinArray.M');
            validatePositiveScalar(m, 'cylinArray.m');
            validatePositiveScalar(r, 'cylinArray.r');
            validatePositiveScalar(H, 'cylinArray.H');
            fBeamUser = getFirstExistingField(A, {'fBeam','fCenter'}, []);
            fBeam = chooseBeamFrequency(fLow, fUp, fBeamUser, 'cylinArray');

            elemPos = makeCylinderPositions(M, m, r, H);
            elemPos = rotateY(elemPos, tilt);

            steerPhi = phi0;
            steerTheta = theta0;

            scanTheta = makeElevationScan(theta0, scanStep);
            AFtheta = arrayFactor(elemPos, fBeam, c, steerPhi, steerTheta, phi0*ones(size(scanTheta)), scanTheta);
            [~, leftEl, rightEl, elevAudit] = halfPowerWidthAndBounds( ...
                scanTheta, abs(AFtheta), theta0, 'bounded', [-90 90]);
            elevAudit.EffectiveRangeDeg = [leftEl, rightEl];
            Pattern2D = makePattern2D(scanTheta, abs(AFtheta), leftEl, rightEl, theta0, ...
                'elevation', '俯仰角 (°)');
            Pattern2D.HPBWAudit = elevAudit;

            [scanAz, scanPhi] = makeCenteredAzimuthCut(phi0, 180, scanStep);
            AFphi = arrayFactor(elemPos, fBeam, c, steerPhi, steerTheta, scanPhi, theta0*ones(size(scanPhi)));
            [~, leftAz, rightAz, azAudit] = halfPowerWidthAndBounds( ...
                scanAz, abs(AFphi), phi0, 'circular', []);
            AzimuthPattern2D = makePattern2D(scanAz, abs(AFphi), leftAz, rightAz, phi0, ...
                'azimuth', '方位角 (°)');
            AzimuthPattern2D.HPBWAudit = azAudit;
            if azAudit.IsFullAzimuth
                AzimuthPattern2D.Wrapped3dBRangeDeg = [-180, 180];
            else
                AzimuthPattern2D.Wrapped3dBRangeDeg = localWrapTo180([leftAz, rightAz]);
            end
            azAudit.EffectiveRangeDeg = AzimuthPattern2D.Wrapped3dBRangeDeg;
            AzimuthPattern2D.HPBWAudit = azAudit;
            AzimuthPattern2D.AngleConvention = 'continuous unwrapped azimuth around steer angle';

            elevRangeCut = [rightEl, leftEl];
            azRangeCut = AzimuthPattern2D.Wrapped3dBRangeDeg;
            notes(end+1) = '圆柱阵：俯仰与方位范围分别使用 elevation / azimuth 主切面插值 HPBW。';
            if strcmp(arrayType, 'cylindrical_vertical')
                notes(end+1) = '圆柱阵垂直模式使用同一圆柱阵几何与两个主切面定义。';
            end

        otherwise
            error('未知阵型：%s', arrayType);
    end

    % 三维连通区投影只用于诊断/审计，不覆盖二维主切面交点。
    Projection3D = projectMainLobe3D(elemPos, fBeam, c, steerPhi, steerTheta, azSearchRange, scan3DStep);

    elevRange = elevRangeCut;     % 几何俯仰 [upper lower]
    azRange = azRangeCut;         % 水平方位 [azLeft azRight]
    Pattern2D.Projection3DRangeDeg = projectionRangeForCut(Pattern2D, Projection3D);
    Pattern2D.ProjectionSource = '3D main-lobe connected component projection (diagnostic only)';

    Sd = centerDepth + mean(elemPos(:,3));
    BeamEq = makeBeamEqFull(Sd, elevRange, azRange, fBeam, arrayType, strjoin(notes, newline));
    BeamEq.Pattern2D = Pattern2D;
    BeamEq.AzimuthPattern2D = AzimuthPattern2D;
    BeamEq.PrincipalCuts = makePrincipalCuts(Pattern2D, AzimuthPattern2D);
    BeamEq.Cut3dBRanges = struct( ...
        'ElevationRangeDeg', elevRange, ...
        'AzimuthRangeDeg', azRange);
    BeamEq.Pattern3D = makePattern3D(elemPos, fBeam, c, BeamEq.AzimuthDeg, BeamEq.ElevationDeg);
    BeamEq.Projection3D = Projection3D;
    BeamEq.ElementCount = size(elemPos, 1);
    BeamEq.ElementPosition = elemPos;
    BeamEq.AzimuthSearchRangeDeg = azSearchRange;

    % V2 weighting model: the two true principal cuts remain independent.
    % Projection3D is deliberately excluded because it is diagnostic only.
    BeamEq.WeightModelVersion = 2;
    BeamEq.ElevationWeightModel = [];
    BeamEq.AzimuthWeightModel = [];
    if strcmpi(Pattern2D.cutName, 'elevation')
        BeamEq.ElevationWeightModel = BuildBeamWeightModelV2(Pattern2D, 'bounded');
    elseif strcmpi(Pattern2D.cutName, 'azimuth')
        BeamEq.AzimuthWeightModel = BuildBeamWeightModelV2(Pattern2D, 'circular');
    end
    if ~isempty(AzimuthPattern2D)
        BeamEq.AzimuthWeightModel = BuildBeamWeightModelV2(AzimuthPattern2D, 'circular');
    end
    BeamEq.SecondaryMainLobeThreshold_dB = -3;

    % 兼容旧字段：旧代码可能读取 OpenAngleAzimuthDeg / OpenAngleElevationDeg
    BeamEq.OpenAngleAzimuthDeg = BeamEq.AzimuthOpenAngleDeg;
    BeamEq.OpenAngleElevationDeg = BeamEq.OpenAngleDeg;

    if doPlot
        figH = plotArrayAndBeam(elemPos, BeamEq, arrayType);
    end
end

% ======================= helper functions =======================
function arrayType = parseArrayType(x)
    if isnumeric(x)
        switch x
            case 1, arrayType = 'vertical';
            case 2, arrayType = 'linear';
            case 3, arrayType = 'cylindrical';
            case 4, arrayType = 'cylindrical'; % 兼容旧编号：4 当前按圆柱阵处理
            case 5, arrayType = 'custom';
            otherwise, error('Beam.arrayType 数值必须为 1/2/3/4/5。');
        end
    else
        s = lower(strrep(strrep(string(x), '-', '_'), '+', '_'));
        switch s
            case {"vertical", "verticalarray", "vertical_line", "垂直阵", "垂直线列阵"}
                arrayType = 'vertical';
            case {"linear", "line", "horiarray", "horizontal", "水平线列阵", "线列阵"}
                arrayType = 'linear';
            case {"cylindrical", "cylinder", "cylinarray", "圆柱阵", ...
                  "cylindrical_vertical", "cylinder_vertical", "圆柱垂直", "圆柱阵垂直"}
                arrayType = 'cylindrical'; % 兼容旧文本：当前等同于圆柱阵
            case {"custom", "自定义", "自定义等效配置"}
                arrayType = 'custom';
            otherwise
                error('无法识别 Beam.arrayType：%s', x);
        end
    end
end

function BeamEq = makeBeamEqFull(Sd, elevRange, azRange, fBeam, arrayType, notes)
    elevRange = normalizeElevRange(elevRange, 'elevRange');
    azRange = normalizeAngleRange(azRange, 'azRange');

    BeamEq = struct();
    BeamEq.Sd = Sd;

    BeamEq.OpenAngleRangeDeg = elevRange;
    BeamEq.OpenAngleDeg = abs(elevRange(1) - elevRange(2));
    BeamEq.ElevationDeg = mean(elevRange);

    BeamEq.AzimuthRangeDeg = azRange;
    BeamEq.AzimuthOpenAngleDeg = angularWidthDeg(azRange);
    BeamEq.AzimuthHalfWidthDeg = BeamEq.AzimuthOpenAngleDeg / 2;
    BeamEq.AzimuthDeg = angularCenterDeg(azRange);

    BeamEq.fBeam = fBeam;
    BeamEq.ArrayType = arrayType;
    BeamEq.Notes = notes;
end

function Projection3D = projectMainLobe3D(elemPos, fBeam, c, phi0, theta0, azSearchRange, scanStep)
% projectMainLobe3D
% 计算完整三维方向图，提取主瓣附近 -3 dB 连通区域，并投影到俯仰/方位范围。

    phiVec = makeAzScanForRange(azSearchRange, scanStep);
    thetaVec = -90:scanStep:90;

    [PHI, THETA] = meshgrid(phiVec, thetaVec);
    AF = zeros(size(PHI));

    for k = 1:numel(PHI)
        AF(k) = calcArrayFactorAtAngle(elemPos, fBeam, c, phi0, theta0, PHI(k), THETA(k));
    end

    AF = abs(AF);
    if max(AF(:)) > 0
        AF = AF ./ max(AF(:));
    end

    hp = 1/sqrt(2);
    mask = AF >= hp;

    % 选择主瓣种子点：优先选择靠近设定轴向且幅值较大的点。
    dPhi = abs(localWrapTo180(PHI - phi0));
    dTheta = abs(THETA - theta0);
    dist = hypot(dPhi, dTheta);
    score = AF - 1e-3 * dist;
    score(~isfinite(score)) = -Inf;
    [~, seedLinear] = max(score(:));
    [seedI, seedJ] = ind2sub(size(AF), seedLinear);

    % 如果种子点未超过 -3 dB，说明主瓣过窄或网格较粗，将其强制纳入，避免空区域。
    if ~mask(seedI, seedJ)
        mask(seedI, seedJ) = true;
    end

    wrapPhi = isFullAzimuthRange(azSearchRange) || isWrapRange(azSearchRange);
    comp = connectedComponent2D(mask, seedI, seedJ, wrapPhi);

    if ~any(comp(:))
        comp(seedI, seedJ) = true;
    end

    thetaVals = THETA(comp);
    phiVals = PHI(comp);

    elevRange = [max(thetaVals), min(thetaVals)];
    azRange = azRangeFromSamples(phiVals, azSearchRange);

    Projection3D = struct();
    Projection3D.ElevationRangeDeg = normalizeElevRange(elevRange, 'Projection3D.ElevationRangeDeg');
    Projection3D.AzimuthRangeDeg = normalizeAngleRange(azRange, 'Projection3D.AzimuthRangeDeg');
    Projection3D.ElevationDeg = mean(Projection3D.ElevationRangeDeg);
    Projection3D.AzimuthDeg = angularCenterDeg(Projection3D.AzimuthRangeDeg);
    Projection3D.OpenAngleDeg = abs(diff(Projection3D.ElevationRangeDeg));
    Projection3D.AzimuthOpenAngleDeg = angularWidthDeg(Projection3D.AzimuthRangeDeg);
    Projection3D.threshold3dB = hp;
    Projection3D.phiVec = phiVec;
    Projection3D.thetaVec = thetaVec;
    Projection3D.PHI = PHI;
    Projection3D.THETA = THETA;
    Projection3D.AF = AF;
    Projection3D.MainLobeMask = comp;
    Projection3D.SteerPhiDeg = phi0;
    Projection3D.SteerThetaDeg = theta0;
    Projection3D.AzimuthSearchRangeDeg = azSearchRange;
end

function range = projectionRangeForCut(P2, Projection3D)
    if isfield(P2, 'cutName') && strcmpi(char(P2.cutName), 'azimuth')
        range = Projection3D.AzimuthRangeDeg;
    else
        range = Projection3D.ElevationRangeDeg;
    end
end

function cuts = makePrincipalCuts(Pattern2D, AzimuthPattern2D)
    cuts = struct();
    if isfield(Pattern2D, 'cutName') && strcmpi(char(Pattern2D.cutName), 'elevation')
        cuts.Elevation = Pattern2D;
    elseif isfield(Pattern2D, 'cutName')
        cuts.Azimuth = Pattern2D;
    end
    if ~isempty(AzimuthPattern2D)
        cuts.Azimuth = AzimuthPattern2D;
    end
end

function comp = connectedComponent2D(mask, seedI, seedJ, wrapPhi)
    [nRow, nCol] = size(mask);
    comp = false(nRow, nCol);

    if seedI < 1 || seedI > nRow || seedJ < 1 || seedJ > nCol || ~mask(seedI, seedJ)
        return;
    end

    stackI = seedI;
    stackJ = seedJ;
    comp(seedI, seedJ) = true;

    neigh = [-1 -1; -1 0; -1 1; 0 -1; 0 1; 1 -1; 1 0; 1 1];

    while ~isempty(stackI)
        i = stackI(end); stackI(end) = [];
        j = stackJ(end); stackJ(end) = [];

        for kk = 1:size(neigh,1)
            ii = i + neigh(kk,1);
            jj = j + neigh(kk,2);

            if ii < 1 || ii > nRow
                continue;
            end

            if jj < 1 || jj > nCol
                if wrapPhi
                    jj = mod(jj-1, nCol) + 1;
                else
                    continue;
                end
            end

            if mask(ii,jj) && ~comp(ii,jj)
                comp(ii,jj) = true;
                stackI(end+1) = ii; %#ok<AGROW>
                stackJ(end+1) = jj; %#ok<AGROW>
            end
        end
    end
end

function phiVec = makeAzScanForRange(range, step)
    range = normalizeAngleRange(range, 'azimuth scan range');

    if isFullAzimuthRange(range)
        phiVec = -180:step:(180-step);
        return;
    end

    if ~isWrapRange(range)
        phiVec = range(1):step:range(2);
        if isempty(phiVec) || abs(phiVec(end) - range(2)) > step/2
            phiVec = [phiVec, range(2)];
        end
    else
        phiVec = [range(1):step:180, -180:step:range(2)];
        phiVec = unique(localWrapTo180(phiVec), 'stable');
    end
end

function tf = isFullAzimuthRange(range)
    range = double(range(:)).';
    % 不调用 angularWidthDeg，避免互相递归。
    tf = abs(range(2)-range(1)) >= 359.999 || ...
         (abs(range(1) + 180) < 1e-9 && abs(range(2) - 180) < 1e-9) || ...
         (abs(range(1) - 180) < 1e-9 && abs(range(2) + 180) < 1e-9);
end

function tf = isWrapRange(range)
    range = double(range(:)).';
    tf = range(1) > range(2) && ~isFullAzimuthRange(range);
end

function range = azRangeFromSamples(phiVals, searchRange)
    phiVals = localWrapTo180(phiVals(:));

    if isempty(phiVals)
        range = searchRange;
        return;
    end

    searchRange = normalizeAngleRange(searchRange, 'searchRange');

    % 若搜索范围本身不跨 ±180，则直接取 min/max，便于与前向扇区 [-90,90] 对齐。
    if ~isFullAzimuthRange(searchRange) && ~isWrapRange(searchRange)
        range = [min(phiVals), max(phiVals)];
        return;
    end

    % 对全方位或跨界范围，取包含样本的最短圆弧。
    vals = sort(phiVals(:));
    vals = unique(vals);

    if numel(vals) == 1
        range = [vals(1), vals(1)];
        return;
    end

    gaps = diff(vals);
    wrapGap = vals(1) + 360 - vals(end);
    gaps = [gaps; wrapGap];

    % 若完整方位搜索域中的圆周采样没有缺口，则主瓣投影就是水平全向。
    % 旧算法仍按“最大缺口的补弧”表示，均匀全圆采样会得到
    % [-179,-180] 一类跨界写法；这里统一规范化为界面口径 [-180,180]。
    positiveGaps = gaps(gaps > 1e-9);
    if isFullAzimuthRange(searchRange) && ~isempty(positiveGaps) && ...
            max(gaps) <= 1.5*median(positiveGaps)
        range = [-180, 180];
        return;
    end

    [~, idxMaxGap] = max(gaps);
    n = numel(vals);

    startIdx = mod(idxMaxGap, n) + 1;
    endIdx = idxMaxGap;

    range = localWrapTo180([vals(startIdx), vals(endIdx)]);
end

function val = getFieldLocal(s, name, defaultVal)
    if isfield(s, name) && ~isempty(s.(name))
        val = s.(name);
    else
        val = defaultVal;
    end
end

function val = getFirstExistingField(s, names, defaultVal)
    val = defaultVal;
    for i = 1:numel(names)
        if isfield(s, names{i}) && ~isempty(s.(names{i}))
            val = s.(names{i});
            return;
        end
    end
end

function A = getRequiredStruct(S, fieldName)
    if ~isfield(S, fieldName) || ~isstruct(S.(fieldName))
        error('缺少结构体字段 Beam.%s。', fieldName);
    end
    A = S.(fieldName);
end

function validatePositiveScalar(x, name)
    if isempty(x) || ~isnumeric(x) || ~isscalar(x) || ~isfinite(x) || x <= 0
        error('%s 必须为正的有限标量。', name);
    end
end

function f = chooseBeamFrequency(fLow, fUp, fUser, paramName)
    if ~isempty(fUser) && isnumeric(fUser) && isscalar(fUser) && fUser > 0
        f = fUser;
        return;
    end
    if isempty(fLow) || isempty(fUp) || fLow <= 0 || fUp <= 0
        error('%s 需要提供有效的频率下限和上限，或提供 fBeam/fCenter。', paramName);
    end
    f = (fLow + fUp) / 2;
end

function scan = makeScan(center, halfWidth, step, lo, hi)
    scan = (center-halfWidth) : step : (center+halfWidth);
    scan = scan(scan >= lo & scan <= hi);
    if ~any(abs(scan-center) < step/2)
        scan = sort([scan, center]);
    end
end

function scan = makeElevationScan(center, step)
% 俯仰是有物理硬边界的变量。始终扫描完整 [-90,90]，使“边界截断”
% 成为可审计的有效结果，而不是因局部扫描域不足产生 NaN。
    if ~isnumeric(center) || ~isscalar(center) || ~isfinite(center) || center < -90 || center > 90
        error('ConfigureArrayBeam:InvalidElevationSteer', ...
            '俯仰指向角必须是 [-90,90] 内的有限标量。');
    end
    scan = -90:step:90;
    if isempty(scan) || ~any(abs(scan-center) < max(step/2, eps))
        scan = sort([scan, center]);
    end
    if scan(1) ~= -90
        scan = [-90, scan];
    end
    if scan(end) ~= 90
        scan = [scan, 90];
    end
    scan = unique(scan, 'sorted');
end

function [scanUnwrapped, scanWrapped] = makeCenteredAzimuthCut(center, halfWidth, step)
% 以指向角为中心在连续展开坐标上扫描，避免主瓣在 +/-180 deg 处被截断。
    center = double(center);
    if ~isscalar(center) || ~isfinite(center)
        error('ConfigureArrayBeam:InvalidAzimuthSteer', ...
            '方位指向角必须是有限标量。');
    end
    delta = (-halfWidth):step:halfWidth;
    if isempty(delta) || ~any(abs(delta) < step/2)
        delta = sort([delta, 0]);
    end
    if abs(delta(1) + halfWidth) > step/2
        delta = [-halfWidth, delta];
    end
    if abs(delta(end) - halfWidth) > step/2
        delta = [delta, halfWidth];
    end
    scanUnwrapped = center + delta;
    scanWrapped = localWrapTo180(scanUnwrapped);
end

function AF = arrayFactor(pos, f, c, phiSteer, thetaSteer, phiScan, thetaScan)
    k = 2*pi*f/c;
    u0 = unitVec(phiSteer, thetaSteer);
    phase0 = pos * u0(:);
    w = exp(-1j*k*phase0);

    AF = zeros(size(phiScan));
    for ii = 1:numel(phiScan)
        u = unitVec(phiScan(ii), thetaScan(ii));
        AF(ii) = sum(w .* exp(1j*k*(pos*u(:)))) / size(pos,1);
    end
    AF = AF ./ max(abs(AF) + eps);
end

function u = unitVec(phiDeg, thetaDeg)
    phi = deg2rad(phiDeg);
    theta = deg2rad(thetaDeg);
    u = [cos(theta)*cos(phi), cos(theta)*sin(phi), sin(theta)];
end

function [width, left, right, audit] = halfPowerWidthAndBounds(angles, amp, center, domainType, domainBounds)
% domainType='bounded'：未遇到交点时使用物理边界，结果仍然有效。
% domainType='circular'：扫描中心两侧完整 180 deg；全周均高于阈值时返回 360 deg。
    if nargin < 4 || isempty(domainType)
        domainType = 'unbounded';
    end
    if nargin < 5
        domainBounds = [];
    end
    if isempty(angles) || isempty(amp)
        width = NaN; left = NaN; right = NaN;
        audit = makeHPBWAudit(NaN, NaN, false, false, false, false, false, true);
        return;
    end
    angles = double(angles(:));
    amp = abs(double(amp(:)));
    if max(amp) > 0
        amp = amp ./ max(amp);
    end

    threshold = 1/sqrt(2);
    thresholdTol = 64*eps(threshold);
    [~, i0] = min(abs(angles-center));

    % 从轴向附近样点爬升到最近的局部峰，避免把采样误差或远处栅瓣当作主瓣。
    while true
        iNext = i0;
        if i0 > 1 && amp(i0-1) > amp(iNext)
            iNext = i0 - 1;
        end
        if i0 < numel(amp) && amp(i0+1) > amp(iNext)
            iNext = i0 + 1;
        end
        if iNext == i0
            break;
        end
        i0 = iNext;
    end

    leftFound = false;
    rightFound = false;
    leftBoundaryLimited = false;
    rightBoundaryLimited = false;
    isFullAzimuth = false;
    isInvalid = false;

    il = i0;
    while il > 1 && amp(il) >= threshold-thresholdTol
        il = il - 1;
    end
    if il == 1 && amp(il) >= threshold-thresholdTol
        left = NaN;
    else
        left = interpCross(angles(il), amp(il), angles(il+1), amp(il+1), threshold);
        leftFound = true;
    end

    ir = i0;
    while ir < numel(angles) && amp(ir) >= threshold-thresholdTol
        ir = ir + 1;
    end
    if ir == numel(angles) && amp(ir) >= threshold-thresholdTol
        right = NaN;
    else
        right = interpCross(angles(ir-1), amp(ir-1), angles(ir), amp(ir), threshold);
        rightFound = true;
    end

    switch lower(char(domainType))
        case 'bounded'
            if ~isnumeric(domainBounds) || numel(domainBounds) ~= 2 || any(~isfinite(domainBounds))
                error('ConfigureArrayBeam:InvalidElevationDomain', ...
                    'bounded HPBW 必须提供两个有限的物理边界。');
            end
            domainBounds = sort(double(domainBounds(:)).');
            if ~leftFound
                left = domainBounds(1);
                leftBoundaryLimited = true;
            end
            if ~rightFound
                right = domainBounds(2);
                rightBoundaryLimited = true;
            end
            width = max(0, right-left);

        case 'circular'
            if leftFound && rightFound
                width = max(0, right-left);
            elseif ~leftFound && ~rightFound && all(amp >= threshold-thresholdTol)
                left = center-180;
                right = center+180;
                width = 360;
                isFullAzimuth = true;
            else
                isInvalid = true;
                width = NaN;
                error('ConfigureArrayBeam:AzimuthHPBWInconsistent', ...
                    ['完整 360 deg 方位主切面未形成一致的 -3 dB 主瓣边界' ...
                     '（center=%.3f deg, peak=%.3f deg, leftFound=%d, rightFound=%d）。'], ...
                    center, angles(i0), leftFound, rightFound);
            end

        otherwise
            if leftFound && rightFound
                width = max(0, right-left);
            else
                width = NaN;
                isInvalid = true;
                warning('ConfigureArrayBeam:HPBWTruncated', ...
                    '主切面扫描域内未找到完整的 -3 dB 交点（center=%.3f deg, peak=%.3f deg）。', ...
                    center, angles(i0));
            end
    end
    audit = makeHPBWAudit(i0, angles(i0), leftFound, rightFound, ...
        leftBoundaryLimited, rightBoundaryLimited, isFullAzimuth, isInvalid);
    audit.PeakAmplitude = amp(i0);
    audit.Left3dB = left;
    audit.Right3dB = right;
    audit.Threshold = threshold;
    audit.EffectiveWidthDeg = width;
    audit.DomainType = char(domainType);
end

function audit = makeHPBWAudit(peakIndex, peakAngle, leftFound, rightFound, ...
        leftBoundaryLimited, rightBoundaryLimited, isFullAzimuth, isInvalid)
    audit = struct();
    audit.PeakIndex = peakIndex;
    audit.PeakAngleDeg = peakAngle;
    audit.LeftCrossingFound = logical(leftFound);
    audit.RightCrossingFound = logical(rightFound);
    audit.LeftBoundaryLimited = logical(leftBoundaryLimited);
    audit.RightBoundaryLimited = logical(rightBoundaryLimited);
    audit.IsBoundaryLimited = logical(leftBoundaryLimited || rightBoundaryLimited);
    audit.IsFullAzimuth = logical(isFullAzimuth);
    audit.IsInvalid = logical(isInvalid);
    % 兼容旧审计字段：物理边界截断是有效状态，不再记为扫描失败。
    audit.IsTruncated = logical(isInvalid);
end

function x = interpCross(x1, y1, x2, y2, y0)
    if abs(y2-y1) < eps
        x = (x1+x2)/2;
    else
        x = x1 + (y0-y1)*(x2-x1)/(y2-y1);
    end
end

function P2 = makePattern2D(angles, AF, left3dB, right3dB, centerAngle, cutName, xLabel)
    angles = double(angles(:));
    AF = abs(double(AF(:)));
    if max(AF) > 0
        AF = AF ./ max(AF);
    end

    P2 = struct();
    P2.scanAngles = angles;
    P2.AF = AF;
    P2.left3dB = left3dB;
    P2.right3dB = right3dB;
    P2.centerAngle = centerAngle;
    P2.cutName = cutName;
    P2.xLabel = xLabel;
    P2.threshold3dB = 1/sqrt(2);
end

function P3 = makePattern3D(elemPos, fBeam, c, azimuthDeg, elevationDeg)
    phiVec = -180:3:177;
    thetaVec = -90:3:90;
    [PHI, THETA] = meshgrid(phiVec, thetaVec);
    AF = zeros(size(PHI));
    for k = 1:numel(PHI)
        AF(k) = calcArrayFactorAtAngle(elemPos, fBeam, c, azimuthDeg, elevationDeg, PHI(k), THETA(k));
    end
    AF = abs(AF);
    if max(AF(:)) > 0
        AF = AF ./ max(AF(:));
    end

    R = AF.^0.8;
    X = R .* cosd(THETA) .* cosd(PHI);
    Y = R .* cosd(THETA) .* sind(PHI);
    Z = R .* sind(THETA);

    P3 = struct();
    P3.X = X; P3.Y = Y; P3.Z = Z; P3.AF = AF;
    P3.PHI = PHI; P3.THETA = THETA;
end

function AF = calcArrayFactorAtAngle(elemPos, f, c, phi0, theta0, phiScan, thetaScan)
    k = 2*pi*f/c;
    u0 = unitVec(phi0, theta0);
    u = unitVec(phiScan, thetaScan);
    du = u - u0;
    phase = k * (elemPos * du(:));
    AF = sum(exp(1j * phase)) / size(elemPos,1);
end

function pos2 = rotateY(pos, deg)
    a = deg2rad(deg);
    R = [cos(a) 0 sin(a); 0 1 0; -sin(a) 0 cos(a)];
    pos2 = (R * pos.').';
end

function pos2 = rotateZ(pos, deg)
    a = deg2rad(deg);
    R = [cos(a) -sin(a) 0; sin(a) cos(a) 0; 0 0 1];
    pos2 = (R * pos.').';
end

function pos = makeCylinderPositions(M, m, r, H)
    az = linspace(0, 2*pi, M+1); az(end) = [];
    if m == 1
        zLevels = 0;
    else
        zLevels = linspace(-H/2, H/2, m);
    end
    pos = zeros(M*m, 3);
    idx = 1;
    for iz = 1:m
        for ia = 1:M
            pos(idx,:) = [r*cos(az(ia)), r*sin(az(ia)), zLevels(iz)];
            idx = idx + 1;
        end
    end
end

function range = normalizeElevRange(range, name)
    if isempty(range) || ~isnumeric(range) || numel(range) ~= 2 || any(~isfinite(range))
        error('%s 必须为包含两个有限数值的角度范围。', name);
    end
    range = double(range(:)).';
    range = max(min(range, 90), -90);
    range = [max(range), min(range)];
end

function range = normalizeAngleRange(range, name)
    if isempty(range) || ~isnumeric(range) || numel(range) ~= 2 || any(~isfinite(range))
        error('%s 必须为包含两个有限数值的角度范围。', name);
    end
    range = double(range(:)).';
    if abs(range(2) - range(1)) >= 359.999
        range = [-180, 180];
    else
        range = localWrapTo180(range);
    end
end

function range = rangeFromCenterWidth(center, width)
    if width >= 359.999
        range = [-180, 180];
    else
        range = localWrapTo180([center - width/2, center + width/2]);
    end
end

function width = angularWidthDeg(range)
    range = double(range(:)).';
    if isFullAzimuthRange(range)
        width = 360;
        return;
    end
    width = mod(range(2) - range(1), 360);
    if width < eps
        width = 0;
    end
end

function center = angularCenterDeg(range)
    if isFullAzimuthRange(range)
        center = 0;
        return;
    end
    width = angularWidthDeg(range);
    center = localWrapTo180(range(1) + width/2);
end

function ang = localWrapTo180(ang)
    ang = mod(ang + 180, 360) - 180;
end

function figH = plotArrayAndBeam(elemPos, BeamEq, arrayType)
    figH = figure('Name', 'Array configuration and equivalent beam', 'Color', 'w');
    tiledlayout(1,2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    if isempty(elemPos)
        plot3(NaN,NaN,NaN);
    else
        scatter3(elemPos(:,1), elemPos(:,2), elemPos(:,3), 45, 'filled');
    end
    grid on; axis equal;
    xlabel('x / m'); ylabel('y / m'); zlabel('z / m');
    title(sprintf('Array geometry: %s', arrayType));

    nexttile;
    hold on; grid on; axis equal;
    quiver3(0,0,0,1,0,0,0,'k','LineWidth',1);
    quiver3(0,0,0,0,1,0,0,'k','LineWidth',1);
    quiver3(0,0,0,0,0,1,0,'k','LineWidth',1);
    u = unitVec(BeamEq.AzimuthDeg, BeamEq.ElevationDeg);
    quiver3(0,0,0,u(1),u(2),u(3),0,'r','LineWidth',2);
    xlabel('x'); ylabel('y'); zlabel('z');
    title(sprintf('ElRange=[%.1f %.1f]°, AzRange=[%.1f %.1f]°', ...
        BeamEq.OpenAngleRangeDeg(1), BeamEq.OpenAngleRangeDeg(2), ...
        BeamEq.AzimuthRangeDeg(1), BeamEq.AzimuthRangeDeg(2)));
end
