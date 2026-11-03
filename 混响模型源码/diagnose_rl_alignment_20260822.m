function diagnose_rl_alignment_20260822
figPath = fullfile(fileparts(mfilename('fullpath')), 'build', 'SYSU', ...
    'validation_output', 'TimeDomainValidation.fig');
f = openfig(figPath, 'invisible');
cleanup = onCleanup(@() close(f)); %#ok<NASGU>
ax = findobj(f, 'Type', 'axes');
rlAx = [];
for i = 1:numel(ax)
    L = findobj(ax(i), 'Type', 'line');
    if numel(L) == 2 && max([L.YData]) > 20
        rlAx = ax(i);
        break;
    end
end
assert(~isempty(rlAx), '未找到 RL 坐标轴。');
L = findobj(rlAx, 'Type', 'line');
for i = 1:numel(L)
    if norm(double(L(i).Color) - [0 0 0]) < 0.1
        meas = double(L(i).YData(:).');
        t = double(L(i).XData(:).');
    elseif norm(double(L(i).Color) - [1 0 0]) < 0.1
        sim = double(L(i).YData(:).');
    end
end
fs = 1 / median(diff(t));
[idxM, infoM] = DetectFirstBottomPeak(meas, t, 'SmoothWindowSec', 0.05);
[idxS, infoS] = DetectFirstBottomPeak(sim, t, 'SmoothWindowSec', 0.05);
fprintf('Detector: meas %.9f s, sim %.9f s, residual %d samples\n', ...
    t(idxM), t(idxS), idxS-idxM);
fprintf('Detector prominence: meas %.6f dB, sim %.6f dB\n', ...
    infoM.MinPeakProminenceDB, infoS.MinPeakProminenceDB);
coarseM = idxM; coarseS = idxS;
rangeM = max(1,coarseM-round(0.60*fs)):min(numel(meas),coarseM+round(1.20*fs));
rangeS = max(1,coarseS-round(0.60*fs)):min(numel(sim),coarseS+round(1.20*fs));
[~,jM] = max(meas(rangeM)); idxM = rangeM(jM);
[~,jS] = max(sim(rangeS)); idxS = rangeS(jS);
fprintf('Formal RL B1 peak: meas %.9f s, sim %.9f s, residual %+d samples (%+.9f s)\n', ...
    t(idxM), t(idxS), idxS-idxM, (idxS-idxM)/fs);


preSec = 0.60; postSec = 1.20;
loM = idxM-round(preSec*fs); hiM = idxM+round(postSec*fs);
loS = idxS-round(preSec*fs); hiS = idxS+round(postSec*fs);
assert(loM>=1 && hiM<=numel(meas) && loS>=1 && hiS<=numel(sim));

smoothList = [0 0.01 0.02 0.05 0.10];
for sw = smoothList
    if sw == 0
        ym = meas; ys = sim;
    else
        w = max(1, round(sw*fs));
        ym = movmean(meas, w); ys = movmean(sim, w);
    end
    [vm, km] = max(ym(loM:hiM)); km = loM+km-1;
    [vs, ks] = max(ys(loS:hiS)); ks = loS+ks-1;
    fprintf('Peak smooth %.3f s: meas %.9f/%.3f, sim %.9f/%.3f, sim-meas %+d samples (%+.6f s)\n', ...
        sw, t(km), vm, t(ks), vs, ks-km, (ks-km)/fs);
end

% 用 B1 局部正式 RL 形状进行归一化互相关诊断。先降采样粗搜，再全采样细搜。
templateM = meas(loM:hiM);
maxRefine = round(0.50*fs);
step = max(1, round(fs/1000));
coarseDeltas = -maxRefine:step:maxRefine;
coarseScore = -inf(size(coarseDeltas));
for j = 1:numel(coarseDeltas)
    d = coarseDeltas(j);
    seg = sim((loS+d):step:(hiS+d));
    ref = templateM(1:step:end);
    coarseScore(j) = localCorrelation(ref, seg);
end
[~, bestJ] = max(coarseScore);
centerDelta = coarseDeltas(bestJ);
fineDeltas = max(-maxRefine,centerDelta-step):min(maxRefine,centerDelta+step);
fineScore = -inf(size(fineDeltas));
for j = 1:numel(fineDeltas)
    d = fineDeltas(j);
    fineScore(j) = localCorrelation(templateM, sim((loS+d):(hiS+d)));
end
[bestScore, bestJ] = max(fineScore);
bestDelta = fineDeltas(bestJ);
fprintf('B1 local RL shape: sim center offset %+d samples (%+.9f s), corr %.9f; recommended extra shift %+d samples\n', ...
    bestDelta, bestDelta/fs, bestScore, -bestDelta);

% 用一阶导数最大值描述肉眼最敏感的上升沿位置。
w = max(1, round(0.02*fs));
ym = movmean(meas,w); ys = movmean(sim,w);
dm = gradient(ym); ds = gradient(ys);
riseLoM = idxM-round(0.40*fs); riseHiM = idxM+round(0.20*fs);
riseLoS = idxS-round(0.40*fs); riseHiS = idxS+round(0.20*fs);
[~, krm] = max(dm(riseLoM:riseHiM)); krm=riseLoM+krm-1;
[~, krs] = max(ds(riseLoS:riseHiS)); krs=riseLoS+krs-1;
fprintf('Rise edge (20 ms smooth): meas %.9f, sim %.9f, sim-meas %+d samples (%+.6f s)\n', ...
    t(krm),t(krs),krs-krm,(krs-krm)/fs);
end

function c = localCorrelation(a,b)
a = double(a(:)); b = double(b(:));
a = a-mean(a,'omitnan'); b = b-mean(b,'omitnan');
den = norm(a)*norm(b);
if den <= 0 || ~isfinite(den), c=-Inf; else, c=(a.'*b)/den; end
end
