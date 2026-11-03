function PrintValidationMetrics(Metrics)
% PrintValidationMetrics
% 在命令行显示实测 vs 仿真验证指标

fprintf('\n');
fprintf('============================================================\n');
fprintf('              实测数据 vs 仿真数据验证指标\n');
fprintf('============================================================\n');

fprintf('评价时间窗: %.3f s  ~  %.3f s\n', Metrics.EvalWindow(1), Metrics.EvalWindow(2));
fprintf('有效样本数: %d\n', Metrics.NumSamples);
fprintf('平滑窗长  : %.3f s\n', Metrics.SmoothWindowSec);
fprintf('PDF bins  : %d\n', Metrics.NumBins);
if isfield(Metrics, 'EvalStartMode')
    fprintf('评价起点模式: %s\n', Metrics.EvalStartMode);
end
if isfield(Metrics, 'IncludeDirectWave') && ~isempty(Metrics.IncludeDirectWave)
    fprintf('计入直达峰及其后段: %d（1=计入，0=从B1开始）\n', Metrics.IncludeDirectWave);
end

if isfield(Metrics, 'WindowInfo')
    fprintf('------------------------------------------------------------\n');
    fprintf('自动窗口检测信息\n');
    fprintf('   方法              : %s\n', Metrics.WindowInfo.Method);
    if isfield(Metrics.WindowInfo, 'DirectTime')
        fprintf('   直达波时间        : %.3f s\n', Metrics.WindowInfo.DirectTime);
    end
    if isfield(Metrics.WindowInfo, 'FirstBottomPeakTime')
        fprintf('   第一个海底反射峰  : %.3f s\n', Metrics.WindowInfo.FirstBottomPeakTime);
    end
    fprintf('   评价起点          : %.3f s\n', Metrics.WindowInfo.EvalStart);
    fprintf('   评价终点          : %.3f s\n', Metrics.WindowInfo.EvalEnd);
    fprintf('   评价窗口长度      : %.3f s\n', Metrics.WindowInfo.EvalDurationSec);
end

if isfield(Metrics, 'LagAlign')
    fprintf('------------------------------------------------------------\n');
    fprintf('第一海底反射峰（B1）共同对齐\n');
    fprintf('   对齐参考          : %s\n', Metrics.LagAlign.Reference);
    fprintf('   外部共同平移      : %.6f s  (%d 点)\n', ...
        Metrics.LagAlign.LagSec, Metrics.LagAlign.LagPts);
    fprintf('   指标内部再次平移  : %d\n', Metrics.LagAlign.AppliedInsideMetrics);
    fprintf('   对齐方法          : %s\n', Metrics.LagAlign.Method);
end

fprintf('------------------------------------------------------------\n');
fprintf('1. 瞬时混响幅度 PDF 分布相似性\n');
fprintf('   BC = %.4f    阈值 >= %.2f    判定: %s\n', ...
    Metrics.PDF_BC, ...
    Metrics.Threshold.PDF_BC, ...
    passText(Metrics.Pass.PDF_BC));

fprintf('------------------------------------------------------------\n');
fprintf('2. 混响强度时域波形相关性\n');
fprintf('   包络相关系数 R_env = %.4f    阈值 >= %.2f    判定: %s\n', ...
    Metrics.EnvelopeCorr, ...
    Metrics.Threshold.EnvelopeCorr, ...
    passText(Metrics.Pass.EnvelopeCorr));

fprintf('   参考：RL 曲线相关系数 R_RL = %.4f\n', Metrics.RLCorr);

fprintf('------------------------------------------------------------\n');
fprintf('3. RL 曲线均方根误差准确度\n');
fprintf('   使用 RLSim/RLMeas 作为 S_i/M_i 计算：\n');
fprintf('   RMSE_RL    = %.6g dB\n', Metrics.RMSE_RL);
fprintf('   sigmaM_RL  = %.6g dB\n', Metrics.SigmaM_RL);
fprintf('   Accuracy_RL = %.2f %%    阈值 >= %.2f %%    判定: %s\n', ...
    Metrics.Accuracy_RL, ...
    Metrics.Threshold.Accuracy, ...
    passText(Metrics.Pass.Accuracy_RL));

fprintf('   参考：电压逐点 Accuracy_Voltage_ref = %.2f %%（不作为正式判据）\n', ...
    Metrics.Accuracy_VoltageRef);

fprintf('------------------------------------------------------------\n');
fprintf('4. 方位历程图可见峰值到达时间误差\n');
fprintf('   %s\n', Metrics.PeakArrivalStatus);

fprintf('============================================================\n\n');

end

function s = passText(flag)
if flag
    s = '通过';
else
    s = '未通过';
end
end
