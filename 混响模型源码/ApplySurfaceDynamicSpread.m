function [hSurfOut, SpreadInfo] = ApplySurfaceDynamicSpread(hSurfIn, fs, U, InputParams)
% ApplySurfaceDynamicSpread
% 第一版海面动态频展/时域展宽后处理函数。
%
% 设计目的：
%   1) 只处理海面/界面散射冲激响应 hSurf；
%   2) 不处理海底混响 hBottom；
%   3) 不处理直达波 hDir；
%   4) 由 App 的“加入海面动态频展”勾选框和海况换算得到的 U 控制强度；
%   5) 后续如果改成事件级 Doppler，只需要替换本函数内部逻辑。
%
% 推荐调用位置：
%   在 ImpulseResponse.m 中 SigCalcuSurface 返回 hSurf 之后、hSca=hBottom+hSurf 之前：
%
%       if OptionBorder == 0 && isfield(InputParams,'EnableSurfaceDynamic') && InputParams.EnableSurfaceDynamic
%           [hSurf, SurfaceSpreadInfo] = ApplySurfaceDynamicSpread(hSurf, fs, U, InputParams);
%       end
%
% 输入：
%   hSurfIn     海面散射冲激响应，可以是行/列向量，也可以是矩阵
%   fs          采样频率 / Hz
%   U           风速 / m/s。模型页可由海况 1–5 级换算得到
%   InputParams 可选结构体，支持字段：
%       EnableSurfaceDynamic              是否启用，默认 true
%       SurfaceDynamic.Strength           展宽倍率，默认 1
%       SurfaceDynamic.SigmaTime          直接指定高斯核标准差 / s
%       SurfaceDynamic.BaseSigmaPerWind   每 1 m/s 风速对应的基准展宽 / s，默认 0.004
%       SurfaceDynamic.PowerLaw           风速指数，默认 1.15
%       SurfaceDynamic.MaxSigmaTime       最大展宽 / s，默认 0.08
%       SurfaceDynamic.MinSigmaTime       最小有效展宽 / s，默认 1/fs
%       SurfaceDynamic.PreserveEnergy     是否保持 hSurf 能量，默认 true
%
% 输出：
%   hSurfOut    展宽后的海面散射冲激响应
%   SpreadInfo  诊断结构体

if nargin < 4 || isempty(InputParams)
    InputParams = struct();
end

hSurfOut = hSurfIn;
SpreadInfo = struct();
SpreadInfo.Method = 'gaussian_time_spread_v1';
SpreadInfo.Enabled = false;
SpreadInfo.Reason = '';
SpreadInfo.U = U;
SpreadInfo.fs = fs;

if isempty(hSurfIn)
    SpreadInfo.Reason = 'empty hSurf';
    return;
end
if nargin < 2 || isempty(fs) || ~isfinite(fs) || fs <= 0
    error('ApplySurfaceDynamicSpread:InvalidFs', 'fs 必须为正数。');
end
if nargin < 3 || isempty(U) || ~isfinite(U)
    U = 0;
end
U = max(0, double(U));

% 如果调用方传了 EnableSurfaceDynamic=false，则直接旁路。
enabled = getNestedField(InputParams, {'SurfaceDynamic','Enable'}, []);
if isempty(enabled)
    enabled = getFieldOrDefault(InputParams, 'EnableSurfaceDynamic', true);
end
enabled = logical(enabled);
if ~enabled
    SpreadInfo.Reason = 'EnableSurfaceDynamic=false';
    return;
end
if U <= 0
    SpreadInfo.Reason = 'U<=0';
    return;
end

strength = getNestedField(InputParams, {'SurfaceDynamic','Strength'}, 1.0);
if isempty(strength) || ~isfinite(strength)
    strength = 1.0;
end
strength = max(0, double(strength));
if strength == 0
    SpreadInfo.Reason = 'Strength=0';
    return;
end

% 第一版采用确定性的高斯时域扩展核。这里的 sigmaTime 是工程调参量，
% 不是严格海面波谱反演结果；后续可以替换为事件级 Doppler 模型。
sigmaTime = getNestedField(InputParams, {'SurfaceDynamic','SigmaTime'}, []);
if isempty(sigmaTime) || ~isfinite(sigmaTime) || sigmaTime <= 0
    baseSigmaPerWind = getNestedField(InputParams, {'SurfaceDynamic','BaseSigmaPerWind'}, 0.004);
    powerLaw = getNestedField(InputParams, {'SurfaceDynamic','PowerLaw'}, 1.15);
    maxSigmaTime = getNestedField(InputParams, {'SurfaceDynamic','MaxSigmaTime'}, 0.080);
    sigmaTime = strength * baseSigmaPerWind * (U ^ powerLaw);
    sigmaTime = min(sigmaTime, maxSigmaTime);
else
    sigmaTime = strength * double(sigmaTime);
end

minSigmaTime = getNestedField(InputParams, {'SurfaceDynamic','MinSigmaTime'}, 1/fs);
if sigmaTime < minSigmaTime
    SpreadInfo.Reason = 'sigmaTime below one sample';
    SpreadInfo.SigmaTime = sigmaTime;
    return;
end

radius = ceil(4 * sigmaTime * fs);
radius = max(1, radius);
tk = (-radius:radius).' / fs;
kernel = exp(-0.5 * (tk / sigmaTime).^2);
kernel = kernel / sum(kernel);

preserveEnergy = getNestedField(InputParams, {'SurfaceDynamic','PreserveEnergy'}, []);
if isempty(preserveEnergy)
    preserveEnergy = getFieldOrDefault(InputParams, 'SurfaceDynamicPreserveEnergy', true);
end
preserveEnergy = logical(preserveEnergy);

origSize = size(hSurfIn);
wasRowVector = isrow(hSurfIn);
h = doubleComplex(hSurfIn);

if isvector(h)
    hCol = h(:);
    hOutCol = conv(hCol, kernel, 'same');
    if preserveEnergy
        hOutCol = preserveEnergyLocal(hCol, hOutCol);
    end
    if wasRowVector
        hSurfOut = hOutCol.';
    else
        hSurfOut = hOutCol;
    end
else
    % 对矩阵沿“时间维”做卷积。通常 hSurface 为 nCell × nTime，时间在第2维。
    if size(h, 2) >= size(h, 1)
        hSurfOut = zeros(size(h));
        for ii = 1:size(h, 1)
            tmp = conv(h(ii, :).', kernel, 'same').';
            if preserveEnergy
                tmp = preserveEnergyLocal(h(ii, :), tmp);
            end
            hSurfOut(ii, :) = tmp;
        end
    else
        hSurfOut = zeros(size(h));
        for jj = 1:size(h, 2)
            tmp = conv(h(:, jj), kernel, 'same');
            if preserveEnergy
                tmp = preserveEnergyLocal(h(:, jj), tmp);
            end
            hSurfOut(:, jj) = tmp;
        end
    end
    hSurfOut = reshape(hSurfOut, origSize);
end

SpreadInfo.Enabled = true;
SpreadInfo.Reason = 'ok';
SpreadInfo.SigmaTime = sigmaTime;
SpreadInfo.SigmaSamples = sigmaTime * fs;
SpreadInfo.KernelRadiusSamples = radius;
SpreadInfo.KernelLength = numel(kernel);
SpreadInfo.Strength = strength;
SpreadInfo.PreserveEnergy = preserveEnergy;
SpreadInfo.EnergyBefore = sum(abs(hSurfIn(:)).^2);
SpreadInfo.EnergyAfter = sum(abs(hSurfOut(:)).^2);

end

% ========================================================================
% Local helper functions
% ========================================================================
function h = doubleComplex(x)
    h = double(real(x)) + 1i * double(imag(x));
end

function y = preserveEnergyLocal(x, y)
    e0 = sum(abs(x(:)).^2);
    e1 = sum(abs(y(:)).^2);
    if isfinite(e0) && isfinite(e1) && e0 > 0 && e1 > 0
        y = y * sqrt(e0 / e1);
    end
end

function val = getFieldOrDefault(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        val = S.(fieldName);
    else
        val = defaultVal;
    end
end

function val = getNestedField(S, pathList, defaultVal)
    if nargin < 3
        defaultVal = [];
    end
    val = defaultVal;
    if ~isstruct(S)
        return;
    end
    cur = S;
    for kk = 1:numel(pathList)
        name = pathList{kk};
        if isstruct(cur) && isfield(cur, name) && ~isempty(cur.(name))
            cur = cur.(name);
        else
            return;
        end
    end
    val = cur;
end
