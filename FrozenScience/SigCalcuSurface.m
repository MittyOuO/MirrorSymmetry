function [TotalTime, hSurf, EventTable] = SigCalcuSurface( ...
        Rd, Sd, RecvRange, Sediment, U, f0, fs, itg, TempWorkDir, ...
        SSP, OriginalDir, Beam, TWindow, Rmax, RandomInfo)
%SigCalcuSurface Generate one immutable surface event realization.
if nargin < 12 || isempty(Beam)
    Beam = getDefaultBeamLocal();
end

if nargin < 13 || isempty(TWindow)
    TWindow = 40;
end

if nargin < 14 || isempty(Rmax)
    Rmax = 50000;
end
if nargin < 15 || isempty(RandomInfo)
    [~, RandomInfo] = ResolveRandomRealization(struct());
end
validateRandomInfoLocal(RandomInfo);

emptyEvent = makeEmptySurfaceEventLocal();

Npoints = ceil(TWindow * fs + 1 );
As = 19 / 10^5 ;
gamma2 = 3.8 ;
ssopt = 1 ;
cw = ResetEnvTop( f0, Sd, Rd, Sediment, TempWorkDir, SSP, Beam );
% ——————————————————————————————————————————————————————————————————
% 1. 在存放.env文件的子文件夹envPath中运行bellhop，并生成.arr和.prt文件
cd(TempWorkDir);

ScatterTimer = tic ;
spmd                                                           % 使用 spmd 分配不同任务
    switch labindex
        case 1
            envFile = 'Surface_StoT';
            bellhop(envFile);
            arrName = fullfile(TempWorkDir, 'Surface_StoT.arr' );
            [result, ~]  = read_arrivals_asc( arrName );
        case 2
            envFile = 'Surface_RtoT';
            bellhop(envFile);
            arrName = fullfile(TempWorkDir,  'Surface_RtoT.arr' );
            [result, ~]   = read_arrivals_asc( arrName );
    end
end

TopArr2 = result{ 1 };
TopBrr2 = result{ 2 };

% ————————————————————————————————————————————————————————————————————————————
% 2. 结构体读取完毕，回到原文件夹中继续进行混响计算流程
cd(OriginalDir);
TopArr2(1).A = 1;
TopArr2(1).delay = 0.0001;
TopBrr2(1).A = 1;
TopBrr2(1).delay = 0.0001;
X = Rmax;                                                       % X计算的最远距离
Y = Rmax;                                                       % Y计算的最远距离
i=30;                                                          % 边长渐变精度参数a= 1/30 = 1/i ,越大精度越大
iplus=100;                                                     % 最小边长精度参数b= 1/100 ,越小精度越大
hSurf = complex(zeros(1, Npoints));
origin=-X;                                                 % 设置x计算起始点
x = origin ;

xValues = [];
while x <=  X
    yAbs = 0;
    while  yAbs <= Y
        yAbs = round( yAbs + abs( yAbs + (x-RecvRange)/2) / i + iplus );
    end
    x = round( x + abs( (x-RecvRange) /2 ) / i + iplus );
    xValues = [ xValues , x ] ;
end

%% 3. 海面散射面元循环
EventCell_all = cell(length(xValues), 1);
for xNum = 1 : length(xValues)
    localEvents = repmat(emptyEvent, 0, 1);
    xLocal = xValues(xNum);
    yAbs = 0;
    breadth = 1;

    while yAbs <= Y
        [DT0_1, DT1_R, ~, CosFi] = TriAngle(0, 0, xLocal, yAbs, RecvRange, 0);
        % 三点：声源投影 A(0,0)，海面散射点 B(x,yAbs)，接收阵中心投影 C(RecvRange,0)
        phiOut = acos(CosFi) * 180 / pi;   % sssnrl 需要的水平夹角，+y/-y 相同

        if (DT0_1 + DT1_R) > 80000
            break;
        end

        if xNum == 1
            long = 1;
        else
            long = round(abs((xLocal - RecvRange) / 2) / i + iplus);
        end
        S = breadth * long;

        % y=0 只算一次；y>0 显式拆成 +y 和 -y 两个面元
        if yAbs == 0
            yList = 0;
        else
            yList = [yAbs, -yAbs];
        end

        for ySigned = yList
            % 声源看向海面散射单元的发射方位角：用于发射方位束控
            phiS = WrapAzimuth180(atan2d(ySigned, xLocal));

            % 接收阵中心看向海面散射单元的方位角：用于后续阵元重构 / BTR / SPDR
            phiR_bearing = WrapAzimuth180(atan2d(ySigned, xLocal - RecvRange));
            cellKey = BuildScatterCellKey('surface', xLocal, ySigned);
            [~, cellKeyId] = StableKeyHash('cell', cellKey);

            % 方位角预筛选。俯仰角仍由每条声线的 srcAngle 在 GetBeamWeight 中联合判断。
            if ~isAzimuthInBeamRangeLocal(phiS, Beam)
                continue;
            end

            for nT1 = 1:TopArr2(DT0_1).Narr
                for nT2 = 1:TopBrr2(DT1_R).Narr

                    AT1 = TopArr2(DT0_1).A(nT1);
                    AT2 = TopBrr2(DT1_R).A(nT2);
                    Tdelay1 = TopArr2(DT0_1).delay(nT1);
                    Tdelay2 = TopBrr2(DT1_R).delay(nT2);
                    TopDelay = Tdelay1 + Tdelay2;

                    thetaIn = TopArr2(DT0_1).RcvrDeclAngle(nT1);
                    thetaOut = TopBrr2(DT1_R).RcvrDeclAngle(nT2);

                    % 保留原有海面路径筛选逻辑
                    if TopArr2(DT0_1).NumBotBnc(nT1) > 1
                        continue;
                    elseif TopBrr2(DT1_R).NumBotBnc(nT2) > 0
                        continue;
                    elseif Tdelay1 == 0 || Tdelay2 == 0
                        continue;
                    elseif TopDelay >= (Npoints - 1) / fs - itg
                        continue;
                    elseif thetaIn >= 0       % 筛选从下方入射到海面的声线
                        continue;
                    elseif thetaOut >= 0      % 筛选从海面出射向下的反向路径
                        continue;
                    end

                    idx = round(TopDelay * fs) + 1;
                    if idx > Npoints || idx <= 0
                        continue;
                    end

                    % 发射束控：只作用于声源 -> 海面散射点的入射路径
                    srcAngle = TopArr2(DT0_1).SrcDeclAngle(nT1);
                    [keepBeam, beamPowerWeight, beamAmpWeight] = GetBeamWeight(srcAngle, phiS, Beam);
                    if ~keepBeam
                        continue;
                    end

                    SSdB = sssnrl(f0, cw, U, As, gamma2, abs(thetaIn), abs(thetaOut), phiOut, ssopt);
                    Ss = 10^(SSdB / 10);

                    counts = [ ...
                        getArrivalFieldValueLocal(TopArr2(DT0_1), 'NumBotBnc', nT1, NaN), ...
                        getArrivalFieldValueLocal(TopArr2(DT0_1), 'NumTopBnc', nT1, NaN), ...
                        getArrivalFieldValueLocal(TopBrr2(DT1_R), 'NumBotBnc', nT2, NaN), ...
                        getArrivalFieldValueLocal(TopBrr2(DT1_R), 'NumTopBnc', nT2, NaN)];
                    pathInstanceKey = BuildScatterPathInstanceKey( ...
                        nT1, nT2, counts, Tdelay1, Tdelay2);
                    [~, pathInstanceId] = StableKeyHash('path', pathInstanceKey);
                    [randomBase, eventKey, eventKeyId] = ScatterEventRandomUnit( ...
                        RandomInfo.RandomSeedUsed, 'surface', cellKey, ...
                        pathInstanceKey, RandomInfo.RandomModelVersion);
                    randomPhase = 2 * pi * randomBase;

                    TPathAmp = AT1 * AT2;
                    % +y/-y 已经显式拆分，每个面元独立随机相位；取消 ComplexGainMirror。
                    SsAmp = sqrt(Ss * S);
                    RandPhase = exp(1i * randomPhase);
                    ComplexGain = TPathAmp * SsAmp * beamAmpWeight * RandPhase;

                    ev = emptyEvent;
                    ev.Delay = TopDelay;
                    ev.ComplexGain = ComplexGain;
                    ev.PowerGain = abs(ComplexGain)^2;
                    ev.PhiS = WrapAzimuth180(phiS);
                    ev.PhiR = WrapAzimuth180(phiR_bearing);
                    ev.X = xLocal;
                    ev.Y = ySigned;
                    ev.Z = 0;
                    ev.CellArea = S;
                    ev.ScatterType = 'surface';
                    ev.InterfaceType = 'surface';
                    ev.SrcAngle = srcAngle;
                    ev.RecvSrcAngle = TopBrr2(DT1_R).SrcDeclAngle(nT2);
                    ev.DelayIn = Tdelay1;
                    ev.DelayOut = Tdelay2;
                    ev.NumBotIn = counts(1);
                    ev.NumTopIn = counts(2);
                    ev.NumBotOut = counts(3);
                    ev.NumTopOut = counts(4);
                    ev.PathClass = classifyPathLocal('surface', counts(1), counts(2), counts(3), counts(4));
                    ev.PathClassID = pathClassIDLocal(ev.PathClass);
                    ev.CellId = cellKeyId;
                    ev.CellKey = cellKey;
                    ev.PathInstanceId = pathInstanceId;
                    ev.PathInstanceKey = pathInstanceKey;
                    ev.EventKey = eventKey;
                    ev.EventKeyId = eventKeyId;
                    ev.RandomSeedUsed = RandomInfo.RandomSeedUsed;
                    ev.RandomModel = RandomInfo.RandomModel;
                    ev.RandomModelVersion = RandomInfo.RandomModelVersion;
                    ev.RandomBase = randomBase;
                    ev.RandomPhase = randomPhase;
                    ev.UsesRandomPhase = true;
                    ev.BeamAmpWeight = beamAmpWeight;
                    ev.BeamPowerWeight = beamPowerWeight;
                    localEvents(end + 1, 1) = ev;
                end
            end
        end

        breadth = round(abs(yAbs + (xLocal - RecvRange) / 2) / i + iplus);
        yAbs = round(yAbs + abs(yAbs + (xLocal - RecvRange) / 2) / i + iplus);
    end

    EventCell_all{xNum} = localEvents;
end

ScatterTime = toc(ScatterTimer);
EventTable = concatEventCellsLocal(EventCell_all, emptyEvent);
hSurf = BuildImpulseResponseFromEvents(EventTable, fs, Npoints);
TotalTime = ScatterTime ;

end

function flag = isAzimuthInBeamRangeLocal(phiDeg, Beam)
% 只做水平方位预筛选。真正的俯仰 + 方位联合权重仍由 GetBeamWeight 完成。
flag = true;
if ~isstruct(Beam) || ~isfield(Beam, 'AzimuthRange') || isempty(Beam.AzimuthRange)
    return;
end

azRange = Beam.AzimuthRange;
if numel(azRange) < 2
    return;
end

az1Raw = azRange(1);
az2Raw = azRange(2);

if abs(az2Raw - az1Raw) >= 359.999 || ...
            (min([az1Raw, az2Raw]) <= -180 && max([az1Raw, az2Raw]) >= 180)
        return;
    end

    phi = WrapAzimuth180(phiDeg);
    az1 = WrapAzimuth180(az1Raw);
    az2 = WrapAzimuth180(az2Raw);

    if az1 <= az2
        flag = (phi >= az1) && (phi <= az2);
    else
        flag = (phi >= az1) || (phi <= az2);
    end
end

function ev = makeEmptySurfaceEventLocal()
    ev = struct();
    ev.Delay = [];
    ev.ComplexGain = [];
    ev.PowerGain = [];
    ev.PhiS = [];
    ev.PhiR = [];
    ev.X = [];
    ev.Y = [];
    ev.Z = [];
    ev.CellArea = [];
    ev.ScatterType = '';
    ev.InterfaceType = '';
    ev.SrcAngle = [];
    ev.RecvSrcAngle = [];
    ev.DelayIn = [];
    ev.DelayOut = [];
    ev.NumBotIn  = [];
    ev.NumTopIn  = [];
    ev.NumBotOut = [];
    ev.NumTopOut = [];
    ev.PathClass = '';
    ev.PathClassID = [];
    ev.BeamAmpWeight = [];
    ev.BeamPowerWeight = [];
    ev.RandomSeedUsed = [];
    ev.RandomModel = '';
    ev.RandomModelVersion = [];
    ev.RandomBase = [];
    ev.RandomPhase = [];
    ev.UsesRandomPhase = [];
    ev.CellId = [];
    ev.CellKey = '';
    ev.PathInstanceId = [];
    ev.PathInstanceKey = '';
    ev.EventKey = '';
    ev.EventKeyId = [];
end

function validateRandomInfoLocal(info)
required = {'RandomSeedUsed','RandomModel','RandomModelVersion'};
for k = 1:numel(required)
    if ~isstruct(info) || ~isfield(info, required{k}) || isempty(info.(required{k}))
        error('SigCalcuSurface:MissingRandomInfo', ...
            'RandomInfo.%s is required.', required{k});
    end
end
end

function EventTable = concatEventCellsLocal(EventCell_all, emptyEvent)
    EventTable = repmat(emptyEvent, 0, 1);
    for ii = 1:numel(EventCell_all)
        if ~isempty(EventCell_all{ii})
            EventTable = [EventTable; EventCell_all{ii}(:)]; %#ok<AGROW>
        end
    end
end
function val = getArrivalFieldValueLocal(S, fieldName, idx, defaultVal)
% getArrivalFieldValueLocal
% 从 Bellhop 到达结构 S 中读取第 idx 条声线的指定字段。
% 如果字段不存在、idx 越界或字段为空，则返回 defaultVal。

    val = defaultVal;

    if ~isstruct(S) || ~isfield(S, fieldName)
        return;
    end

    tmp = S.(fieldName);

    if isempty(tmp)
        return;
    end

    if numel(tmp) >= idx
        val = tmp(idx);
    end
end


function cls = classifyPathLocal(interfaceType, nbIn, ntIn, nbOut, ntOut)
% classifyPathLocal
% 根据入射段和出射段的海底/海面反射次数，为事件生成路径族标签。
%
% interfaceType : 'bottom' / 'surface' / 'direct'
% nbIn, ntIn    : 声源 -> 散射点 路径中的海底/海面反射次数
% nbOut, ntOut  : 散射点 -> 接收点 路径中的海底/海面反射次数

    nbIn  = sanitizeBounceCountLocal(nbIn);
    ntIn  = sanitizeBounceCountLocal(ntIn);
    nbOut = sanitizeBounceCountLocal(nbOut);
    ntOut = sanitizeBounceCountLocal(ntOut);

    if nargin < 1 || isempty(interfaceType)
        interfaceType = 'unknown';
    end

    interfaceType = lower(char(interfaceType));

    cls = sprintf('%s_B%dT%d_to_B%dT%d', ...
        interfaceType, nbIn, ntIn, nbOut, ntOut);
end


function id = pathClassIDLocal(cls)
% pathClassIDLocal
% 将 PathClass 字符串转换为一个稳定的数值 ID，便于后续统计或筛选。
% 注意：正式显示仍建议使用 PathClass 字符串，PathClassID 主要用于辅助索引。

    if isempty(cls)
        id = 0;
        return;
    end

    cls = char(cls);

    % 简单稳定 hash，避免使用 containers.Map，方便 parfor / 打包环境
    id = uint32(5381);
    for kk = 1:numel(cls)
        id = uint32(mod(double(id) * 33 + double(cls(kk)), 2^32 - 1));
    end
    id = double(id);
end


function n = sanitizeBounceCountLocal(x)
% sanitizeBounceCountLocal
% 将 Bellhop 到达结构中的反射次数整理为非负整数。
% 若字段缺失或为 NaN，则记为 -1，表示 unknown。

    if isempty(x) || ~isnumeric(x) || ~isfinite(x)
        n = -1;
    else
        n = round(double(x(1)));
    end
end

