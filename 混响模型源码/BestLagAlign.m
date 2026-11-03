function [simAligned, measAligned, lagPts, lagSec, bestCorr] = BestLagAlign(measRef, simRef, simTarget, fs, maxLagSec)
% BestLagAlign
% 在 [-maxLagSec, +maxLagSec] 范围内寻找使 simRef 与 measRef 相关性最高的滞后量，
% 并将同样的滞后量应用到 simTarget。
%
% lagPts > 0 表示将仿真序列向后延迟；
% lagPts < 0 表示将仿真序列向前提前。

measRef = measRef(:);
simRef = simRef(:);
simTarget = simTarget(:);

N = min([length(measRef), length(simRef), length(simTarget)]);
measRef = measRef(1:N);
simRef = simRef(1:N);
simTarget = simTarget(1:N);

maxLagPts = max(0, round(maxLagSec * fs));

bestCorr = -Inf;
bestLag = 0;

for lag = -maxLagPts : maxLagPts

    if lag > 0
        idxMeas = (1 + lag) : N;
        idxSim  = 1 : (N - lag);
    elseif lag < 0
        lagAbs = abs(lag);
        idxMeas = 1 : (N - lagAbs);
        idxSim  = (1 + lagAbs) : N;
    else
        idxMeas = 1:N;
        idxSim  = 1:N;
    end

    x = measRef(idxMeas);
    y = simRef(idxSim);

    x = x - mean(x, 'omitnan');
    y = y - mean(y, 'omitnan');

    if std(x, 'omitnan') < eps || std(y, 'omitnan') < eps
        c = -Inf;
    else
        C = corrcoef(x, y, 'Rows', 'complete');
        c = C(1, 2);
    end

    if isfinite(c) && c > bestCorr
        bestCorr = c;
        bestLag = lag;
    end
end

lagPts = bestLag;
lagSec = lagPts / fs;

% 按最优 lag 输出裁剪后的序列
if lagPts > 0
    idxMeas = (1 + lagPts) : N;
    idxSim  = 1 : (N - lagPts);
elseif lagPts < 0
    lagAbs = abs(lagPts);
    idxMeas = 1 : (N - lagAbs);
    idxSim  = (1 + lagAbs) : N;
else
    idxMeas = 1:N;
    idxSim  = 1:N;
end

measAligned = measRef(idxMeas);
simAligned = simTarget(idxSim);

end