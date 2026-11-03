function [St] = GenerateBurstSignal(F0, B, Fs, Itg)
% GenerateBurstSignal 生成用于卷积的爆炸宽带信号
% F0: 中心频率
% B: 带宽 (供用户下拉选择，如 500 或 1000)
% Fs: 采样率
% Itg: 信号持续时间

% 1. 生成理想爆炸冲击波
Tau = 0.002;
TimeVec = 0 : 1/Fs : Itg;
SIdeal = exp(-TimeVec / Tau);

% 2. 带通滤波
FLow = F0 - B/2;
FHigh = F0 + B/2;

% 防止频率越界保护
if FLow <= 10
    FLow = 10;
end
if FHigh >= Fs/2
    FHigh = Fs/2 - 100;
end

[BFilt, AFilt] = butter(4, [FLow, FHigh] / (Fs/2));
StFiltered = filter(BFilt, AFilt, SIdeal);

% 3. 峰值归一化 (无论滤波损耗多少，强制最大值为1，确保后续幅值绝对可控)
St = StFiltered / max(abs(StFiltered));

end