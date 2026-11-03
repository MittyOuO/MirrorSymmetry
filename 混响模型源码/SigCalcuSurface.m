function  [TotalTime, hSurf, EventTable] = SigCalcuSurface(Rd, Sd, RecvRange, Sediment, U, f0, fs, itg, TempWorkDir, SSP, OriginalDir, Beam,TWindow, Rmax,SaveEvents)
if nargin < 12 || isempty(Beam)
    Beam = getDefaultBeamLocal();
end

if nargin < 13 || isempty(TWindow)
    TWindow = 40;
end

if nargin < 14 || isempty(SaveEvents)
    SaveEvents = false;
end

SaveEvents = logical(SaveEvents);

emptyEvent = makeEmptySurfaceEventLocal();

Npoints = ceil(TWindow * fs + 1 );
As = 19 / 10^5 ;
gamma2 = 3.8 ;
% 0表示采用NRL总海面散射：界面分量+气泡云体积散射分量。
ssopt = 0 ;
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
hSurf = zeros(1, Npoints);
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
hSurface = zeros(length(xValues), Npoints);
EventCell_all = cell(length(xValues), 1);
for xNum = 1 : length(xValues)
    surfaceTemp = zeros(1, Npoints);
    localEvents = repmat(emptyEvent, 0, 1);    x = xValues( xNum );
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
            phiS = atan2d(ySigned, xLocal);

            % 接收阵中心看向海面散射单元的方位角：用于后续阵元重构 / BTR / SPDR
            phiR_bearing = atan2d(ySigned, xLocal - RecvRange);

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

                    TPathAmp = AT1 * AT2;
                    % +y/-y 已经显式拆分，每个面元独立随机相位；取消 ComplexGainMirror。
                    SsAmp = sqrt(Ss * S);
                    RandPhase = exp(1i * 2 * pi * rand());
                    ComplexGain = TPathAmp * SsAmp * beamAmpWeight * RandPhase;
                    surfaceTemp(idx) = surfaceTemp(idx) + ComplexGain;



                    if SaveEvents
                        ev = emptyEvent;
                        ev.Delay = TopDelay;
                        ev.ComplexGain = ComplexGain;
                        ev.PowerGain = abs(ComplexGain)^2;
                        ev.PhiS = phiS;
                        ev.PhiR = phiR_bearing;
                        ev.X = xLocal;
                        ev.Y = ySigned;
                        ev.Z = 0;
                        ev.CellArea = S;
                        ev.ScatterType = 'surface';
                        ev.SrcAngle = srcAngle;
                        ev.RecvSrcAngle = TopBrr2(DT1_R).SrcDeclAngle(nT2);
                        ev.DelayIn = Tdelay1;
                        ev.DelayOut = Tdelay2;
                        
                        ev.NumBotIn  = getArrivalFieldValueLocal(TopArr2(DT0_1), 'NumBotBnc', nT1, NaN);
                        ev.NumTopIn  = getArrivalFieldValueLocal(TopArr2(DT0_1), 'NumTopBnc', nT1, NaN);
                        ev.NumBotOut = getArrivalFieldValueLocal(TopBrr2(DT1_R), 'NumBotBnc', nT2, NaN);
                        ev.NumTopOut = getArrivalFieldValueLocal(TopBrr2(DT1_R), 'NumTopBnc', nT2, NaN);
                        ev.PathClass = classifyPathLocal('surface', ...
                            ev.NumBotIn, ev.NumTopIn, ev.NumBotOut, ev.NumTopOut);
                        ev.PathClassID = pathClassIDLocal(ev.PathClass);

                        ev.BeamAmpWeight = beamAmpWeight;
                        ev.BeamPowerWeight = beamPowerWeight;

                        localEvents(end + 1, 1) = ev;
                    end
                end
            end
        end

        breadth = round(abs(yAbs + (xLocal - RecvRange) / 2) / i + iplus);
        yAbs = round(yAbs + abs(yAbs + (xLocal - RecvRange) / 2) / i + iplus);
    end

    hSurface(xNum, :) = surfaceTemp;
    EventCell_all{xNum} = localEvents;
end

hSurf = sum(hSurface, 1);
ScatterTime = toc(ScatterTimer);

if SaveEvents
    EventTable = concatEventCellsLocal(EventCell_all, emptyEvent);
else
    EventTable = [];
end
TotalTime = ScatterTime ;

end

function flag = isAzimuthInBeamRangeLocal(phiDeg, Beam)
% 只做水平方位预筛选，必须保留水平主瓣和左右旁瓣。
% 真正的俯仰 + 方位联合权重仍由 GetBeamWeight 完成。
flag = true;
if ~isstruct(Beam) || ~isfield(Beam, 'AzimuthRange') || isempty(Beam.AzimuthRange)
    return;
end

azRange = Beam.AzimuthRange;
if numel(azRange) ~= 2
    return;
end
flag = isAngleInAzimuthRangeLocal(phiDeg,azRange);
if flag
    return;
end

if isfield(Beam,'AzimuthSideRange') && isequal(size(Beam.AzimuthSideRange),[2 2])
    for row = 1:2
        rangeNow = Beam.AzimuthSideRange(row,:);
        if azimuthWidthLocal(rangeNow) > 1e-9 && ...
                isAngleInAzimuthRangeLocal(phiDeg,rangeNow)
            flag = true;
            return;
        end
    end
end
end

function flag = isAngleInAzimuthRangeLocal(phiDeg,rangeDeg)
if azimuthWidthLocal(rangeDeg) >= 359.999
    flag = true;
    return;
end
phi = wrapTo180Local(phiDeg);
az1 = wrapTo180Local(rangeDeg(1));
az2 = wrapTo180Local(rangeDeg(2));
if az1 <= az2
    flag = (phi >= az1-1e-9) && (phi <= az2+1e-9);
else
    flag = (phi >= az1-1e-9) || (phi <= az2+1e-9);
end
end

function width = azimuthWidthLocal(rangeDeg)
if abs(double(rangeDeg(2))-double(rangeDeg(1))) >= 359.999
    width = 360;
else
    width = mod(double(rangeDeg(2))-double(rangeDeg(1)),360);
end
end

function ang = wrapTo180Local(ang)
    ang = mod(ang + 180, 360) - 180;
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

