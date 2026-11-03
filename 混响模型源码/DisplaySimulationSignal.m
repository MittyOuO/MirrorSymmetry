function [vTotal, RLCurve, timeRt] = DisplaySimulationSignal(yDir, ySca, timeRt, fs, f0, B, SourceLevel, Sensitivity, AmpGain, NL)
% DisplaySimulationSignal 生成带底噪的最终电压信号并绘制时域与混响级图 (纯仿真模式)
% 输入:
%   yDir, ySca: 纯理论直达波与散射波 (无量纲)
%   timeRt, fs, f0, B: 时间轴, 采样率, 中心频率, 带宽
%   SourceLevel, Sensitivity, AmpGain, NL: 声源级, 灵敏度, 放大增益, 环境底噪

% --- 1. 合成原始纯净信号 ---
yTotal = yDir + ySca;

% --- 2. 物理映射 (无量纲 -> 电压 V) ---
% 综合系统增益：将理论值放大到真实的水听器输出量级
systemGain = 10^((SourceLevel + Sensitivity + AmpGain) / 20);
vSignalSim = yTotal * systemGain;

% --- 3. 生成真实的海洋本底电噪声 ---
% 噪声声压(uPa) = 10^(NL/20) -> 转换为电压 RMS
vNoiseRms = 10^(NL / 20) * 10^((Sensitivity + AmpGain) / 20);

% 时域电压叠加 (真实的示波器波形，包含随机毛刺)
vNoise = vNoiseRms * randn(size(vSignalSim));
vTotal = real(vSignalSim + vNoise); % 提取实部，去除复数警告

% --- 4. 计算混响级 (RL) - 严格的能量叠加 ---
windowSize = round(0.05 * fs); % 50ms 平滑窗

% 计算纯信号的滑动平均能量
energySignal = movmean(abs(vSignalSim).^2, windowSize);
% 纯噪声的恒定平均能量
energyNoise = vNoiseRms^2;

% 总能量 = 信号能量 + 噪声能量 (不相关信号的交叉项为0)
energyTotal = energySignal + energyNoise;

% 换算回环境中的声压级 RL
RLCurve = 10 * log10(energyTotal) - (Sensitivity + AmpGain);

% %% --- 5. 绘图展示 ---
% figure('Name', '纯仿真时域与混响级展示', 'Position', [100, 100, 1000, 800]);
% 
% 图 1: 时域电压波形
subplot(2, 1, 1);
plot(timeRt, vTotal, 'b', 'LineWidth', 1);
grid on;
xlabel('Time (s)', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel('Voltage (V)', 'FontName', 'Times New Roman', 'FontSize', 12);
title(sprintf('Simulated Time-Domain Signal (f_0 = %d Hz, B = %d Hz)', f0, B), 'FontSize', 14);
xlim([0, max(timeRt)]);

% 图 2: 混响级曲线
subplot(2, 1, 2);
plot(timeRt, RLCurve, 'r', 'LineWidth', 1.5);
grid on;
xlabel('Time (s)', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel('Reverberation Level (dB re 1\muPa)', 'FontName', 'Times New Roman', 'FontSize', 12);
title('Simulated Reverberation Level', 'FontSize', 14);
xlim([0, max(timeRt)]);
ylim([NL - 10, max(RLCurve) + 10]); % 根据底噪动态调整Y轴下限
end