function [simAligned, measAligned, idxMeas, idxSim, Nout] = ApplyKnownLag(meas, sim, lagPts)
% ApplyKnownLag
% 将已知 lag 应用于 sim，并裁剪 meas/sim 到共同有效长度。
%
% lagPts > 0：仿真序列向后延迟；
% lagPts < 0：仿真序列向前提前。

meas = meas(:);
sim = sim(:);

N = min(length(meas), length(sim));
meas = meas(1:N);
sim = sim(1:N);

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

measAligned = meas(idxMeas);
simAligned = sim(idxSim);
Nout = length(measAligned);

end