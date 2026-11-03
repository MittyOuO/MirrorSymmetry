function [RLFast, timeAxis, FastInfo] = FastRLCompute(InputParams, OptionBorder, varargin)
% FastRLCompute
% 指定阵元计算模式下使用的"中心频率能量快速计算"函数。
%
% 目的：
%   1) 只在中心频率/等效工作频率处进行平均能量叠加；
%   2) 快速输出 RLFast(t) 与 TimeCost.FastRL；
%   3) 不生成保留相位信息的事件表，不用于 BTR/SPDR/阵元波形重构的最终结果。
%
% 推荐调用位置：
%   App 的【指定阵元计算】模式中，点击"开始仿真"后先调用本函数；
%   绘制快速 RL 后，再重新开始计时，调用保留相位信息的事件表计算流程。
%
% 输入：
%   InputParams : 模型输入结构体，常用字段包括：
%       .Rd, .Sd, .RecvRange, .Sediment, .SSP
%       .Tht, .Miu, .v, .f0/.fCW/.fStart/.fEnd, .fs, .Itg, .U
%       .Beam, .TWindow/.TWindowCompute, .SourceLevel, .NL
%       .sigMod, .TpCW, .TpHFM
%   OptionBorder : 0 = 海底 + 海面；1 = 仅海底。默认 1。
%
% 可选 Name-Value：
%   'RecvRange'       : 覆盖 InputParams.RecvRange，用于指定阵元距离。
%   'TempWorkDir'     : 指定临时目录；默认 tempname。若由 RunReverbSimulation 传入，则本函数不删除该目录。
%   'KeepTempFiles'   : true/false，默认 false。
%   'UseParallel'     : true/false，默认 true。仅用于面元循环 parfor。
%   'StartParallelPool': true/false，默认 true。若为 true，则在计时前启动并行池。
%   'Rmax'            : 计算边界，m；默认 InputParams.Rmax 或 60000。
%
% 输出：
%   RLFast  : 快速 RL 曲线，dB re 1 uPa。
%   timeAxis: 时间轴，s。
%   FastInfo: 诊断信息结构体：
%       .TimeCost.FastRL         快速 RL 主计算耗时，不包含并行池启动。
%       .TimeCost.ParallelSetup  并行池启动耗时。
%       .TimeCost.Total          函数总耗时。
%       .FrequencyUsed           快速计算使用的频率，Hz。
%       .IRSca/.IRDir/.IRSurf/.IRTotal
%       .PulseDuration/.PulseLength
%
% 重要说明：
%   本函数是独立快速计算入口。即使后续删除 SigCalcuBottom/SigCalcuSurface
%   中旧的平均能量叠加分支，本函数仍可作为"单频点快速计算能力"的展示入口。

    if nargin < 2 || isempty(OptionBorder)
        OptionBorder = 1;
    end

    opt = parseOptionsLocal(varargin{:});

     % 并行池由 FastRLCompute 统一确保开启；并行池启动不计入 FastRL 主计算耗时。
    if opt.StartParallelPool && opt.UseParallel
        if isempty(gcp('nocreate'))
            parpool;
        end
    end

    % -----------------------------
    % 1. 解析输入参数
    % -----------------------------
    Params = normalizeInputParams(InputParams, opt);
    Params.OptionBorder = OptionBorder;

    % -----------------------------
    % 2. 使用 RunReverbSimulation 创建的共享临时目录
    % -----------------------------
    TempWorkDir = Params.TempWorkDir;
    if isempty(TempWorkDir) || ~isfolder(TempWorkDir)
        error(['FastRLCompute 需要由 RunReverbSimulation 传入已存在的共享临时目录 TempWorkDir。', ...
               '请在调用时使用 ''TempWorkDir'', TempWorkDir。']);
    end
    OriginalDir = pwd;
    cd(OriginalDir);
    
    % -----------------------------
    % 3. 快速能量计算：海底 + 可选海面
    % -----------------------------
    fastTimer = tic;

    [IRSca, IRDir, bottomInfo] = calcBottomFastEnergy(Params, TempWorkDir, OriginalDir, opt);

    IRSurf = zeros(size(IRSca));
    surfaceInfo = struct();
    if OptionBorder == 0
        [IRSurf, surfaceInfo] = calcSurfaceFastEnergy(Params, TempWorkDir, OriginalDir, opt);
    end

    IRTotalRaw = real(IRSca + IRDir + IRSurf);
    IRTotalRaw(IRTotalRaw < 0) = 0;

    % -----------------------------
    % 4. 用真实脉冲持续时间进行快速能量平滑
    % -----------------------------
    [TpEff, pulseInfo] = getEffectivePulseDurationLocal(Params);
    pulseLen = max(1, round(TpEff * Params.fs));
    pulseKernel = ones(1, pulseLen);
    IRTotal = conv(IRTotalRaw, pulseKernel, 'same');
    fastCost = toc(fastTimer) ;
    % -----------------------------
    % 5. 快速 RL：中心频率能量 + 理论噪声底
    % -----------------------------
    SL = getFieldOrDefaultLocal(InputParams, 'SourceLevel', 0);
    NL = getFieldOrDefaultLocal(InputParams, 'NL', -Inf);

    signalEnergy = 10.^(SL ./ 10) .* IRTotal;
    if isfinite(NL)
        noiseEnergy = 10.^(NL ./ 10);
    else
        noiseEnergy = 0;
    end

    RLFast = 10 .* log10(max(signalEnergy + noiseEnergy, realmin));
    RLFast = RLFast(:);
    timeAxis = (0:numel(RLFast)-1).' ./ Params.fs;
    

    % -----------------------------
    % 6. 打包输出
    % -----------------------------
    FastInfo = struct();
    FastInfo.Method = 'center_frequency_energy_fast_RL';
    FastInfo.FrequencyUsed = Params.fFast;
    FastInfo.fs = Params.fs;
    FastInfo.RecvRange = Params.RecvRange;
    FastInfo.OptionBorder = OptionBorder;
    FastInfo.PulseDuration = TpEff;
    FastInfo.PulseLength = pulseLen;
    FastInfo.PulseInfo = pulseInfo;
    FastInfo.IRSca = IRSca(:);
    FastInfo.IRDir = IRDir(:);
    FastInfo.IRSurf = IRSurf(:);
    FastInfo.IRTotalRaw = IRTotalRaw(:);
    FastInfo.IRTotal = IRTotal(:);
    FastInfo.SignalEnergy = signalEnergy(:);
    FastInfo.NoiseEnergy = noiseEnergy;
    FastInfo.SourceLevel = SL;
    FastInfo.NL = NL;
    FastInfo.BottomInfo = bottomInfo;
    FastInfo.SurfaceInfo = surfaceInfo;
    FastInfo.TimeCost = struct();
    FastInfo.TimeCost.FastRL = fastCost ;
end
% ========================================================================
function opt = parseOptionsLocal(varargin)
    opt = struct();
    opt.RecvRange = [];
    opt.TempWorkDir = '';
    opt.UseParallel = true;
    opt.StartParallelPool = true;
    opt.Rmax = [];

    if mod(numel(varargin), 2) ~= 0
        error('可选参数必须以 Name-Value 形式给出。');
    end
    for k = 1:2:numel(varargin)
        name = lower(string(varargin{k}));
        value = varargin{k+1};
        switch name
            case "recvrange"
                opt.RecvRange = value;
            case "tempworkdir"
                opt.TempWorkDir = char(value);
            case "keeptempfiles"
                opt.KeepTempFiles = logical(value);
            case "useparallel"
                opt.UseParallel = logical(value);
            case "startparallelpool"
                opt.StartParallelPool = logical(value);
            case "rmax"
                opt.Rmax = value;
            otherwise
                error('未知可选参数：%s。', name);
        end
    end

    % 当前版本不再在 FastRLCompute 内部新建临时目录；
    % TempWorkDir 必须由 RunReverbSimulation 创建并通过 Name-Value 传入。
end

% ========================================================================
function Params = normalizeInputParams(InputParams, opt)
    Params = struct();
    Params.Rd = getRequiredFieldLocal(InputParams, 'Rd');
    Params.Sd = getRequiredFieldLocal(InputParams, 'Sd');

    if isempty(opt.RecvRange)
        Params.RecvRange = getRequiredFieldLocal(InputParams, 'RecvRange');
    else
        Params.RecvRange = opt.RecvRange;
    end
    if Params.RecvRange == 0
        Params.RecvRange = 1;
    end

    Params.Sediment = getRequiredFieldLocal(InputParams, 'Sediment');
    Params.SSP = getRequiredFieldLocal(InputParams, 'SSP');
    Params.fs = getRequiredFieldLocal(InputParams, 'fs');
    Params.Itg = getFieldOrDefaultLocal(InputParams, 'Itg', 0.02);
    Params.U = getFieldOrDefaultLocal(InputParams, 'U', 0);

    Params.fFast = getFastFrequency(InputParams);

    Tht = getFieldOrDefaultLocal(InputParams, 'Tht', 10);
    if abs(Tht) > pi
        Tht = deg2rad(Tht);
    end
    Params.Tht = Tht;

    MiuRaw = getFieldOrDefaultLocal(InputParams, 'Miu', -32);
    if MiuRaw <= 0
        Params.Miu = 10.^(MiuRaw ./ 10);
    else
        Params.Miu = MiuRaw;
    end

    vRaw = getFieldOrDefaultLocal(InputParams, 'v', -10);
    if vRaw <= 0
        Params.v = 10.^(vRaw ./ 10);
    else
        Params.v = vRaw;
    end

    Params.Beam = getFieldOrDefaultLocal(InputParams, 'Beam', getDefaultBeamLocal());

    % 保留发射信号脉宽/类型字段，用于快速 RL 的脉冲能量铺展。
    Params.sigMod = getFieldOrDefaultLocal(InputParams, 'sigMod', []);
    Params.sigType = getFieldOrDefaultLocal(InputParams, 'sigType', '');
    Params.TpCW = getFieldOrDefaultLocal(InputParams, 'TpCW', 0.2);
    Params.TpHFM = getFieldOrDefaultLocal(InputParams, 'TpHFM', 0.2);
    Params.PulseDuration = getFieldOrDefaultLocal(InputParams, 'PulseDuration', []);

    if isfield(InputParams, 'TWindowCompute') && ~isempty(InputParams.TWindowCompute)
        TWindow = InputParams.TWindowCompute;
    elseif isfield(InputParams, 'TWindow') && ~isempty(InputParams.TWindow)
        TWindow = InputParams.TWindow;
    elseif isfield(InputParams, 'TWindowDisplay') && ~isempty(InputParams.TWindowDisplay)
        TWindow = min(InputParams.TWindowDisplay, 80);
    else
        TWindow = 50;
    end
    Params.TWindow = TWindow;
    Params.Npoints = ceil(TWindow * Params.fs + 1);

    if isempty(opt.Rmax)
        Params.Rmax = getFieldOrDefaultLocal(InputParams, 'Rmax', 60000);
    else
        Params.Rmax = opt.Rmax;
    end
    if Params.Rmax < 1000
        % 若用户误以 km 输入，则转成 m。
        Params.Rmax = Params.Rmax * 1000;
    end
    if ~isempty(opt.TempWorkDir)
        Params.TempWorkDir = opt.TempWorkDir;
    elseif isfield(InputParams, 'TempWorkDir') && ~isempty(InputParams.TempWorkDir)
        Params.TempWorkDir = InputParams.TempWorkDir;
    else
        Params.TempWorkDir = '';
    end
end

% ========================================================================
function fFast = getFastFrequency(InputParams)
    if isfield(InputParams, 'f0') && ~isempty(InputParams.f0) && isfinite(InputParams.f0) && InputParams.f0 > 0
        fFast = InputParams.f0;
        return;
    end

    sigMod = getFieldOrDefaultLocal(InputParams, 'sigMod', []);
    if isempty(sigMod)
        sigType = lower(string(getFieldOrDefaultLocal(InputParams, 'sigType', '')));
        switch sigType
            case "cw"
                sigMod = 1;
            case "hfm"
                sigMod = 2;
            case "hfm_cw"
                sigMod = 3;
            case "cw_hfm"
                sigMod = 4;
            otherwise
                sigMod = 2;
        end
    end

    switch sigMod
        case 1
            fFast = getFieldOrDefaultLocal(InputParams, 'fCW', 500);
        case {2,3,4}
            fStart = getFieldOrDefaultLocal(InputParams, 'fStart', []);
            fEnd = getFieldOrDefaultLocal(InputParams, 'fEnd', []);
            if isempty(fStart) || isempty(fEnd)
                fFast = getFieldOrDefaultLocal(InputParams, 'fCW', 500);
            else
                fFast = (fStart + fEnd) / 2;
            end
        otherwise
            if isfield(InputParams, 'Band') && numel(InputParams.Band) == 2
                fFast = mean(InputParams.Band);
            else
                fFast = getFieldOrDefaultLocal(InputParams, 'fCW', 500);
            end
    end
end

% ========================================================================
function [IRSca, IRDir, info] = calcBottomFastEnergy(P, TempWorkDir, OriginalDir, opt)
    info = struct();
    info.Component = 'bottom';

    ResetEnvBottom(P.fFast, P.Sd, P.Rd, P.RecvRange, P.Sediment, TempWorkDir, P.SSP, P.Beam);

    % 仿照 SigCalcuBottom：写好 .env 后，并行运行三组 Bellhop 并读取到达结构。
    cd(TempWorkDir);

    baseNames = {'Bottom_StoB', 'Bottom_BtoR', 'Bottom_StoR'};
    spmd
        localArr = [];
        if labindex <= 3
            localArr = runSingleBellhopRead(baseNames{labindex}, TempWorkDir);
        end
    end
    ArrStoB = localArr{1};
    ArrBtoR = localArr{2};
    ArrStoR = localArr{3};


    cd(OriginalDir);

    ArrStoB(1).A = 1; ArrStoB(1).delay = 0.0001;
    ArrBtoR(1).A = 1; ArrBtoR(1).delay = 0.0001;

    X = P.Rmax;
    Y = P.Rmax;
    gridI = 30;
    iplus = 100;
    nn = 1;

    IRSca = zeros(1, P.Npoints);
    IRDir = zeros(1, P.Npoints);

    xValues = buildXValues(X, P.RecvRange, gridI, iplus);
    hIR_all = zeros(numel(xValues), P.Npoints);
    

    parfor xNum = 1:numel(xValues)
        hIR_all(xNum, :) = bottomOneXEnergy(xValues(xNum), xNum, X, Y, P, ArrStoB, ArrBtoR, gridI, iplus, nn);
    end


    IRSca = sum(hIR_all, 1);

    % 直达波/多途能量，使用 phiDirect=0° 进行发射束控判断。
    Rec = 2;
    if Rec <= numel(ArrStoR) && ArrStoR(Rec).Narr > 0
        DirectPath = ArrStoR(Rec);
        for k = 1:DirectPath.Narr
            AmpDir = DirectPath.A(k);
            delayDir = DirectPath.delay(k);
            srcAngleDir = DirectPath.SrcDeclAngle(k);
            [keepBeamDir, beamPowerWeightDir, ~] = GetBeamWeight(srcAngleDir, 0, P.Beam);
            if ~keepBeamDir
                continue;
            end
            idx = round(delayDir * P.fs) + 1;
            if idx > 0 && idx <= P.Npoints
                IRDir(idx) = IRDir(idx) + abs(AmpDir).^2 .* beamPowerWeightDir;
            end
        end
    end
end

% ========================================================================
function hIRtemp = bottomOneXEnergy(xLocal, xNum, X, Y, P, ArrStoB, ArrBtoR, gridI, iplus, nn) 
    hIRtemp = zeros(1, P.Npoints);
    yAbs = 0;
    breadth = 1;

    while yAbs <= Y
        [DT0_1, DT1_R, ~, CosFi] = TriAngle(0, 0, xLocal, yAbs, P.RecvRange, 0);
        if (DT0_1 + DT1_R) > 80000
            break;
        end

        if xNum == 1
            long = 1;
        else
            long = round(abs((xLocal - P.RecvRange) / 2) / gridI + iplus);
        end
        S = breadth * long;

        isFullAz = isFullAzimuthBeam(P.Beam);
        if yAbs == 0
            yList = 0;
            yWeightList = 1;
        elseif isFullAz
            yList = yAbs;
            yWeightList = 2;
        else
            yList = [yAbs, -yAbs];
            yWeightList = [1, 1];
        end

        for iy = 1:numel(yList)
            ySigned = yList(iy);
            yWeight = yWeightList(iy);

            phiS = atan2d(ySigned, xLocal);
            if ~isAzimuthInBeamRange(phiS, P.Beam)
                continue;
            end

            for n1 = 1:ArrStoB(DT0_1).Narr
                for n2 = 1:ArrBtoR(DT1_R).Narr
                    AmpIn = ArrStoB(DT0_1).A(n1);
                    DelayIn = ArrStoB(DT0_1).delay(n1);
                    AmpOut = ArrBtoR(DT1_R).A(n2);
                    DelayOut = ArrBtoR(DT1_R).delay(n2);
                    TotalDelay = DelayIn + DelayOut;

                    if DelayIn == 0 || DelayOut == 0
                        continue;
                    end
                    if TotalDelay >= (P.Npoints - 1) / P.fs - P.Itg
                        continue;
                    end

                    srcAngle = ArrStoB(DT0_1).SrcDeclAngle(n1);
                    [keepBeam, beamPowerWeight, ~] = GetBeamWeight(srcAngle, phiS, P.Beam);
                    if ~keepBeam
                        continue;
                    end

                    [ms1, ms2] = ScatterFunc(abs(ArrStoB(DT0_1).RcvrDeclAngle(n1)), ...
                        abs(ArrBtoR(DT1_R).SrcDeclAngle(n2)), CosFi, P.Tht, P.Miu, nn);
                    Sb = ms1 + P.v * ms2;
                    PowerGain = abs(AmpIn).^2 .* abs(AmpOut).^2 .* Sb .* S .* beamPowerWeight;
                    PowerGain = yWeight .* PowerGain;

                    idx = round(TotalDelay * P.fs) + 1;
                    if idx > 0 && idx <= P.Npoints
                        hIRtemp(idx) = hIRtemp(idx) + PowerGain;
                    end
                end
            end
        end

        breadth = round(abs(yAbs + (xLocal - P.RecvRange) / 2) / gridI + iplus);
        yAbs = round(yAbs + abs(yAbs + (xLocal - P.RecvRange) / 2) / gridI + iplus);
    end
end

% ========================================================================
function [IRSurf, info] = calcSurfaceFastEnergy(P, TempWorkDir, OriginalDir, opt)
    info = struct();
    info.Component = 'surface';
    cw = ResetEnvTop(P.fFast, P.Sd, P.Rd, P.Sediment, TempWorkDir, P.SSP, P.Beam);
    

    % 仿照 SigCalcuSurface：写好 .env 后，并行运行两组 Bellhop 并读取到达结构。
    cd(TempWorkDir);
    
    baseNames = {'Surface_StoT', 'Surface_RtoT'};
    spmd
        localArr = [];
        if labindex <= 2
            localArr = runSingleBellhopRead(baseNames{labindex}, TempWorkDir);
        end
    end
    TopStoT = localArr{1};
    TopRtoT = localArr{2};

    cd(OriginalDir);

    TopStoT(1).A = 1; TopStoT(1).delay = 0.0001;
    TopRtoT(1).A = 1; TopRtoT(1).delay = 0.0001;

    X = P.Rmax;
    Y = P.Rmax;
    gridI = 30;
    iplus = 100;
    As = 19 / 10^5;
    gamma2 = 3.8;
    % 与保相时域路径一致：海面总散射包含界面与气泡云体积分量。
    ssopt = 0;

    xValues = buildXValues(X, P.RecvRange, gridI, iplus);
    hSurf_all = zeros(numel(xValues), P.Npoints);

    parfor xNum = 1:numel(xValues)
        hSurf_all(xNum, :) = surfaceOneXEnergy(xValues(xNum), xNum, X, Y, P, TopStoT, TopRtoT, cw, As, gamma2, ssopt, gridI, iplus);
    end

    IRSurf = sum(hSurf_all, 1);
end

% ========================================================================
function hSurfTemp = surfaceOneXEnergy(xLocal, xNum, X, Y, P, TopStoT, TopRtoT, cw, As, gamma2, ssopt, gridI, iplus) %#ok<INUSL>
    hSurfTemp = zeros(1, P.Npoints);
    yAbs = 0;
    breadth = 1;

    while yAbs <= Y
        [DT0_1, DT1_R, ~, CosFi] = TriAngle(0, 0, xLocal, yAbs, P.RecvRange, 0);
        phiOut = acos(CosFi) * 180 / pi;
        if (DT0_1 + DT1_R) > 80000
            break;
        end

        if xNum == 1
            long = 1;
        else
            long = round(abs((xLocal - P.RecvRange) / 2) / gridI + iplus);
        end
        S = breadth * long;

        isFullAz = isFullAzimuthBeam(P.Beam);
        if yAbs == 0
            yList = 0;
            yWeightList = 1;
        elseif isFullAz
            yList = yAbs;
            yWeightList = 2;
        else
            yList = [yAbs, -yAbs];
            yWeightList = [1, 1];
        end

        for iy = 1:numel(yList)
            ySigned = yList(iy);
            yWeight = yWeightList(iy);

            phiS = atan2d(ySigned, xLocal);
            if ~isAzimuthInBeamRange(phiS, P.Beam)
                continue;
            end

            for nT1 = 1:TopStoT(DT0_1).Narr
                for nT2 = 1:TopRtoT(DT1_R).Narr
                    AT1 = TopStoT(DT0_1).A(nT1);
                    AT2 = TopRtoT(DT1_R).A(nT2);
                    Tdelay1 = TopStoT(DT0_1).delay(nT1);
                    Tdelay2 = TopRtoT(DT1_R).delay(nT2);
                    TopDelay = Tdelay1 + Tdelay2;
                    thetaIn = TopStoT(DT0_1).RcvrDeclAngle(nT1);
                    thetaOut = TopRtoT(DT1_R).RcvrDeclAngle(nT2);

                    if TopStoT(DT0_1).NumBotBnc(nT1) > 1
                        continue;
                    elseif TopRtoT(DT1_R).NumBotBnc(nT2) > 0
                        continue;
                    elseif Tdelay1 == 0 || Tdelay2 == 0
                        continue;
                    elseif TopDelay >= (P.Npoints - 1) / P.fs - P.Itg
                        continue;
                    elseif thetaIn >= 0
                        continue;
                    elseif thetaOut >= 0
                        continue;
                    end

                    srcAngle = TopStoT(DT0_1).SrcDeclAngle(nT1);
                    [keepBeam, beamPowerWeight, ~] = GetBeamWeight(srcAngle, phiS, P.Beam);
                    if ~keepBeam
                        continue;
                    end

                    SSdB = sssnrl(P.fFast, cw, P.U, As, gamma2, abs(thetaIn), abs(thetaOut), phiOut, ssopt);
                    Ss = 10.^(SSdB ./ 10);
                    PowerGain = abs(AT1).^2 .* abs(AT2).^2 .* Ss .* S .* beamPowerWeight;
                    PowerGain = yWeight .* PowerGain;

                    idx = round(TopDelay * P.fs) + 1;
                    if idx > 0 && idx <= P.Npoints
                        hSurfTemp(idx) = hSurfTemp(idx) + PowerGain;
                    end
                end
            end
        end

        breadth = round(abs(yAbs + (xLocal - P.RecvRange) / 2) / gridI + iplus);
        yAbs = round(yAbs + abs(yAbs + (xLocal - P.RecvRange) / 2) / gridI + iplus);
    end
end

% ========================================================================
function xValues = buildXValues(X, RecvRange, gridI, iplus)
    origin = -X;
    x = origin;
    xValues = [];

    while x <= X
        x = round(x + abs((x - RecvRange) / 2) / gridI + iplus);
        xValues = [xValues, x]; 
    end
end


% ========================================================================
function Arr = runSingleBellhopRead(baseName, TempWorkDir)
    arrName = fullfile(TempWorkDir, [baseName, '.arr']);
    if exist(arrName, 'file')
        delete(arrName);
    end

    bellhop(baseName);

    if ~exist(arrName, 'file')
        error('未找到 Bellhop 输出文件：%s', arrName);
    end
    [Arr, ~] = read_arrivals_asc(arrName);
end

% ========================================================================
function [TpEff, info] = getEffectivePulseDurationLocal(P)
    sigMod = getFieldOrDefaultLocal(P, 'sigMod', []);
    if isempty(sigMod)
        sigType = lower(string(getFieldOrDefaultLocal(P, 'sigType', '')));
        switch sigType
            case "cw"
                sigMod = 1;
            case "hfm"
                sigMod = 2;
            case "hfm_cw"
                sigMod = 3;
            case "cw_hfm"
                sigMod = 4;
            otherwise
                sigMod = 2;
        end
    end

    TpCW = getFieldOrDefaultLocal(P, 'TpCW', 0.2);
    TpHFM = getFieldOrDefaultLocal(P, 'TpHFM', 0.2);

    switch sigMod
        case 1
            TpEff = TpCW;
            method = 'TpCW';
        case 2
            TpEff = TpHFM;
            method = 'TpHFM';
        case {3,4}
            TpEff = TpCW + TpHFM;
            method = 'TpCW_plus_TpHFM';
        otherwise
            TpEff = getFieldOrDefaultLocal(P, 'PulseDuration', max(TpCW, TpHFM));
            method = 'fallback';
    end

    TpEff = max(TpEff, 1 / P.fs);
    info = struct('sigMod', sigMod, 'Method', method, 'TpCW', TpCW, 'TpHFM', TpHFM);
end

% ========================================================================
function flag = isAzimuthInBeamRange(phiDeg, Beam)
    flag = true;
    if ~isstruct(Beam) || ~isfield(Beam, 'AzimuthRange') || isempty(Beam.AzimuthRange)
        return;
    end

    az = double(Beam.AzimuthRange(:).');
    az = az(isfinite(az));
    if numel(az) < 2
        return;
    end

    rawLeft = az(1);
    rawRight = az(2);

    % [-180, 180]、[0, 360] 等写法均视为全方位。
    if abs(rawRight - rawLeft) >= 359.999
        flag = true;
        return;
    end

    azLeft = wrapTo180Local(rawLeft);
    azRight = wrapTo180Local(rawRight);
    phi = wrapTo180Local(phiDeg);

    if azLeft <= azRight
        flag = (phi >= azLeft) && (phi <= azRight);
    else
        flag = (phi >= azLeft) || (phi <= azRight);
    end
end

% ========================================================================
function a = wrapTo180Local(a)
    a = mod(a + 180, 360) - 180;
    if a == -180
        a = 180;
    end
end

% ========================================================================
function Beam = getDefaultBeamLocal()
    Beam = struct();
    Beam.OpenAngle = [90, -90];
    Beam.MainBeam = Beam.OpenAngle;
    Beam.AzimuthRange = [-180, 180];
    Beam.SideRange = [-90 -90; 90 90];
    Beam.SideDown_dB = [0 0];
    Beam.ElevSideDown_dB = [0 0];
    Beam.AzimuthSideRange = [-180 -180; 180 180];
    Beam.AzimuthSideDown_dB = [0 0];
end

% ========================================================================
function val = getRequiredFieldLocal(S, fieldName)
    if ~isstruct(S) || ~isfield(S, fieldName) || isempty(S.(fieldName))
        error('InputParams.%s 不能为空。', fieldName);
    end
    val = S.(fieldName);
end

% ========================================================================
function val = getFieldOrDefaultLocal(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        val = S.(fieldName);
    else
        val = defaultVal;
    end
end
function flag = isFullAzimuthBeam(Beam)
    flag = true;

    if ~isstruct(Beam)
        return;
    end

    if isfield(Beam, 'AzimuthRange') && ~isempty(Beam.AzimuthRange)
        az = double(Beam.AzimuthRange(:).');
        az = az(isfinite(az));

        if numel(az) >= 2
            flag = abs(az(2) - az(1)) >= 359.999;
        end
    end
end
