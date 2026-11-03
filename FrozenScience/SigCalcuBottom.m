function [TotalTime, hSca, hDir, EventTable, EventTableDirect, GridAudit] = SigCalcuBottom( ...
        Rd, Sd, RecvRange, Sediment, Tht, Miu, v, f0, fs, itg, ...
        TempWorkDir, SSP, OriginalDir, Beam, TWindow, Rmax, RandomInfo,G3Config)
%SigCalcuBottom Generate one immutable bottom/direct event realization.

if nargin < 16 || isempty(Rmax)
    Rmax = 50000;
end
if nargin < 17 || isempty(RandomInfo)
    [~, RandomInfo] = ResolveRandomRealization(struct());
end
validateRandomInfoLocal(RandomInfo);
if nargin < 18 || isempty(G3Config) || ~isfield(G3Config,'DomainResolved')
    legacyDomainInput=struct('RecvRange',RecvRange,'Rmax',Rmax,'fs',fs,'TWindow',TWindow);
    [domain,~]=ResolveBottomDomain(legacyDomainInput,'single_direct');
    G3Config=struct('DomainResolved',domain, ...
        'Model',struct('DisableAdditionalRandomPhase',false), ...
        'RecvRange',RecvRange);
end
D=G3Config.DomainResolved;
disableAdditionalRandomPhase=false;
if isfield(G3Config,'Model') && isfield(G3Config.Model,'DisableAdditionalRandomPhase')
    disableAdditionalRandomPhase=logical(G3Config.Model.DisableAdditionalRandomPhase);
end
emptyEvent = makeEmptyBottomEventLocal();
emptyDirectEvent = makeEmptyBottomEventLocal();
DirectEvents = repmat(emptyDirectEvent, 0, 1);

Npoints = ceil(TWindow * fs + 1 );

ResetEnvBottom(f0,Sd,Rd,Sediment,TempWorkDir,SSP,Beam,D.PropagationSpec, ...
    bottomDepthFromSSPLocal(SSP));

% ——————————————————————————————————————————————————————————————————
% 1. 在存放.env文件的子文件夹envPath中运行bellhop，并生成.arr和.prt文件
% envList = dir(fullfile(TempWorkDir,'*.env'));
cd(TempWorkDir);
% envName = {envList.name} ;



ScatterTimer = tic;
bottomEnvFiles = {'Bottom_BtoR', 'Bottom_StoB', 'Bottom_StoR'};
bottomArrFiles = {'Bottom_BtoR.arr', 'Bottom_StoB.arr', 'Bottom_StoR.arr'};

missingEnv = {};
for ii = 1:numel(bottomEnvFiles)
    if ~exist(fullfile(TempWorkDir, [bottomEnvFiles{ii}, '.env']), 'file')
        missingEnv{end+1} = [bottomEnvFiles{ii}, '.env']; 
    end
end

if ~isempty(missingEnv)
    error('ResetEnvBottom 未生成完整的海底传播环境文件，缺少：%s', strjoin(missingEnv, ', '));
end

spmd(3)
    envFile = bottomEnvFiles{labindex};
    bellhop(envFile);

    arrName = fullfile(TempWorkDir, bottomArrFiles{labindex});
    if ~exist(arrName, 'file')
        error('Bellhop 未生成到达文件：%s', arrName);
    end

    [result, ~] = read_arrivals_asc(arrName);
end


% 将 Composite 对象转换为普通数组
Arr2 = result{ 2 };     % 声源 -> 海底散射点
Brr2 = result{ 1 };     % 海底散射点 -> 接收点
RArr2 = result{ 3 };    % 声源 -> 接收点直达/多途

% ————————————————————————————————————————————————————————————————————————————
% 2. 结构体读取完毕，回到原文件夹中继续进行混响计算流程
cd(OriginalDir);
Arr2(1).A = 1;
Arr2(1).delay = 0.0001;
Brr2(1).A = 1;
Brr2(1).delay = 0.0001;                                    % 注意 A是脉冲响应的振幅
nn=1 ;



X = D.XmaxM;
Y = D.YmaxM;
i = D.GridI;
iplus = D.GridIPlusM;
hSca = complex(zeros(1, Npoints));
hDir = complex(zeros(1, Npoints));
[xValues,xWidthsM] = BuildBottomXValues(X,RecvRange,i,iplus,D.BoundaryPolicy);
[GridAudit,~] = AuditProductionBottomGrid(G3Config,'single');

%% ————————————————————————————————————————————————————————————————————————————
% 3. 散射面元循环
%    为节省计算时间对x进行parfor循环计算
%    yAbs = 0 只计算一次；yAbs > 0 显式计算 +yAbs / -yAbs 两个面元。
%    因此：
%      1) 非相干模式取消原来的 *2；
%      2) 相干模式取消 ComplexGainMirror；
%      3) 每个带符号面元独立生成随机相位；
%      4) 每个带符号面元独立记录事件表。
% ————————————————————————————————————————————————————————————————————————————
EventCell_all = cell(length(xValues), 1);

% 加入【三维方位扩展】：
% 对每一个 yAbs > 0 的散射面元，同时显式计算 +yAbs 和 -yAbs 两个镜像面元。
% 这样可以分别计算 phiS / phiR_bearing，并分别进入发射束控、接收阵列响应或事件表记录。
% 注意：显式计算 +y/-y 后，不再使用原来的 *2 镜像能量补偿；
%       相干模式下也不再用 ComplexGainMirror 代替 -y 面元。

parfor xNum = 1 : length(xValues)
    localEvents = repmat(emptyEvent, 0, 1);
    xLocal = xValues(xNum);
    gridRow = BuildBottomGridRow(xLocal,xWidthsM(xNum),Y,RecvRange, ...
        i,iplus,D.TotalTwoLegHorizontalRangeLimitM,D.BoundaryPolicy);

    for gridIndex=1:numel(gridRow.Y)
        if ~gridRow.Within80kmMask(gridIndex)
            break
        end
        ySigned=gridRow.Y(gridIndex);
        S=gridRow.CellArea(gridIndex);
        [DT0_1,DT1_R,~,CosFi] = TriAngle(0,0,xLocal,ySigned,RecvRange,0);
            phiS = WrapAzimuth180(atan2d(ySigned, xLocal));
            phiR_bearing = WrapAzimuth180(atan2d(ySigned, xLocal - RecvRange));
            cellKey = BuildScatterCellKey('bottom', xLocal, ySigned);
            [~, cellKeyId] = StableKeyHash('cell', cellKey);

            if ~isAzimuthInBeamRangeLocal(phiS, Beam)     % 方位角预筛选：如果该带符号面元完全不在发射方位范围内，直接跳过。
                continue;                                 % 垂直出射角仍在每条声线中由 GetBeamWeight 联合判断。
            end

            for n1 = 1 : Arr2(DT0_1).Narr                                  % 循环声源→海底传播方式
                for n2 = 1 : Brr2(DT1_R).Narr                                    % 循环海底→接收器传播方式

                    % A. 读取复数传播幅度与时延
                    AmpIn = Arr2(DT0_1).A(n1);      % 入射复数幅度
                    DelayIn = Arr2(DT0_1).delay(n1);
                    AmpOut = Brr2(DT1_R).A(n2);     % 出射复数幅度
                    DelayOut = Brr2(DT1_R).delay(n2);
                    TotalDelay = DelayIn + DelayOut ;

                    % B. 去除无效声线和超出时间窗的声线
                    if DelayIn == 0 || DelayOut == 0
                        continue;
                    end
                    if TotalDelay >= (Npoints - 1) / fs - itg
                        continue;
                    end

                    idx = round(TotalDelay * fs) + 1;
                    if idx > Npoints || idx <= 0
                        continue;
                    end

                    % C. 发射束控：垂直出射角 + 水平方位角联合判断
                    % srcAngle 为垂直出射角，phiS 为水平发射方位角。
                    srcAngle = Arr2(DT0_1).SrcDeclAngle(n1);
                    [keepBeam, beamPowerWeight, beamAmpWeight] = GetBeamWeight(srcAngle, phiS, Beam);
                    if ~keepBeam
                        continue;
                    end

                    % D. 散射强度
                    [ms1, ms2] = ScatterFunc(abs(Arr2(DT0_1).RcvrDeclAngle(n1)), ...
                        abs(Brr2(DT1_R).SrcDeclAngle(n2)), ...
                        CosFi, Tht, Miu, nn);
                    Sb = ms1 + v * ms2;

                    counts = [ ...
                        getArrivalFieldValueLocal(Arr2(DT0_1), 'NumBotBnc', n1, NaN), ...
                        getArrivalFieldValueLocal(Arr2(DT0_1), 'NumTopBnc', n1, NaN), ...
                        getArrivalFieldValueLocal(Brr2(DT1_R), 'NumBotBnc', n2, NaN), ...
                        getArrivalFieldValueLocal(Brr2(DT1_R), 'NumTopBnc', n2, NaN)];
                    pathInstanceKey = BuildScatterPathInstanceKey( ...
                        n1, n2, counts, DelayIn, DelayOut);
                    [~, pathInstanceId] = StableKeyHash('path', pathInstanceKey);
                    phaseInfo=ResolveEventPhase(RandomInfo,'bottom',cellKey, ...
                        pathInstanceKey,disableAdditionalRandomPhase);
                    randomBase=phaseInfo.RandomBase;
                    eventKey=phaseInfo.EventKey;
                    eventKeyId=phaseInfo.EventKeyId;
                    randomPhase=phaseInfo.RandomPhase;

                    PathAmp = AmpIn * AmpOut;

                    % 考虑相位模式：复幅度 h(t) 叠加，+y/-y 面元已经显式拆分，每个面元独立随机相位。
                    ScatAmp = sqrt(Sb * S);
                    ComplexGain = PathAmp * ScatAmp * beamAmpWeight * phaseInfo.Multiplier;

                    % E. 事件表是该次实现的唯一事实源。
                    ev = emptyEvent;
                    ev.Delay = TotalDelay;
                    ev.ComplexGain = ComplexGain;
                    ev.PowerGain = abs(ComplexGain)^2;
                    ev.PhiS = WrapAzimuth180(phiS);
                    ev.PhiR = WrapAzimuth180(phiR_bearing);
                    ev.X = xLocal;
                    ev.Y = ySigned;
                    ev.Z = bottomDepthFromSSPLocal(SSP);
                    ev.CellArea = S;
                    ev.ScatterType = 'bottom';
                    ev.InterfaceType = 'bottom';
                    ev.SrcAngle = srcAngle;
                    ev.RecvSrcAngle = Brr2(DT1_R).SrcDeclAngle(n2);
                    ev.DelayIn = DelayIn;
                    ev.DelayOut = DelayOut;
                    ev.NumBotIn = counts(1);
                    ev.NumTopIn = counts(2);
                    ev.NumBotOut = counts(3);
                    ev.NumTopOut = counts(4);
                    ev.PathClass = classifyPathLocal('bottom', counts(1), counts(2), counts(3), counts(4));
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
                    ev.UsesRandomPhase = phaseInfo.UsesRandomPhase;
                    ev.BeamAmpWeight = beamAmpWeight;
                    ev.BeamPowerWeight = beamPowerWeight;
                    localEvents(end + 1, 1) = ev;
                end
            end
    end
    EventCell_all{xNum} = localEvents;
end

ScatterTime = toc(ScatterTimer);
EventTable = concatEventCellsLocal(EventCell_all, emptyEvent);
hSca = BuildImpulseResponseFromEvents(EventTable, fs, Npoints);


%%  4. 直达波分量计算
%    直达波对应接收点位于 x 正半轴，水平方位角取 phiDirect = 0°。
DirectTimer = tic ;
Rec = 2;

if Rec <= length(RArr2) && RArr2(Rec).Narr > 0
    DirectPath = RArr2(Rec) ;% 提取目标结构体

    for k = 1 : DirectPath.Narr    % 遍历每一条到达声线 (不需要 t 循环！)
        AmpDir = DirectPath.A(k);
        delayDir = DirectPath.delay(k);                % 提取时延
        n_bot = double(DirectPath.NumBotBnc(k));       % 获取触底次数

        srcAngleDir = DirectPath.SrcDeclAngle(k);
        phiDirect = WrapAzimuth180(0);
        [keepBeamDir, beamPowerWeightDir, beamAmpWeightDir] = GetBeamWeight(srcAngleDir, phiDirect, Beam);
        if ~keepBeamDir
            continue;
        end

        % 粗糙度修正因子：保留原结构，当前默认不引入额外损失
        Loss_Roughness_dB = 0.0;
        if n_bot > 0
            Roughness_Factor = 10^(-(n_bot * Loss_Roughness_dB) / 20);
            AmpDir = AmpDir * Roughness_Factor;
        end

        idx = round(delayDir * fs) + 1;
        if idx <= 0 || idx > length(hDir)
            continue;
        end
        ComplexGain = AmpDir * beamAmpWeightDir;
        counts = [n_bot, getArrivalFieldValueLocal(DirectPath, 'NumTopBnc', k, NaN), 0, 0];
        cellKey = BuildScatterCellKey('direct', RecvRange, 0);
        pathInstanceKey = BuildScatterPathInstanceKey(k, 0, counts, delayDir, 0);
        [~, cellKeyId] = StableKeyHash('cell', cellKey);
        [~, pathInstanceId] = StableKeyHash('path', pathInstanceKey);
        eventKey = sprintf('direct|%s|%s', cellKey, pathInstanceKey);
        [~, eventKeyId] = StableKeyHash('event', eventKey);
        evd = emptyDirectEvent;
        evd.Delay = delayDir;
        evd.ComplexGain = ComplexGain;
        evd.PowerGain = abs(ComplexGain)^2;
        evd.PhiS = phiDirect;
        evd.PhiR = phiDirect;
        evd.X = RecvRange;
        evd.Y = 0;
        evd.Z = Rd;
        evd.CellArea = NaN;
        evd.ScatterType = 'direct';
        evd.InterfaceType = 'direct';
        evd.SrcAngle = srcAngleDir;
        evd.RecvSrcAngle = getArrivalFieldValueLocal(DirectPath, 'RcvrDeclAngle', k, NaN);
        evd.DelayIn = delayDir;
        evd.DelayOut = 0;
        evd.NumBotIn = counts(1);
        evd.NumTopIn = counts(2);
        evd.NumBotOut = counts(3);
        evd.NumTopOut = counts(4);
        evd.CellId = cellKeyId;
        evd.CellKey = cellKey;
        evd.PathInstanceId = pathInstanceId;
        evd.PathInstanceKey = pathInstanceKey;
        evd.EventKey = eventKey;
        evd.EventKeyId = eventKeyId;
        evd.RandomSeedUsed = RandomInfo.RandomSeedUsed;
        evd.RandomModel = RandomInfo.RandomModel;
        evd.RandomModelVersion = RandomInfo.RandomModelVersion;
        evd.RandomBase = 0;
        evd.RandomPhase = 0;
        evd.UsesRandomPhase = false;
        evd.BeamAmpWeight = beamAmpWeightDir;
        evd.BeamPowerWeight = beamPowerWeightDir;
        DirectEvents(end + 1, 1) = evd;
    end
else
    warning('未找到接收点 %d 的直达波数据，请检查 Bellhop 设置或 RArr2 结构。', Rec);
end
DirectTime = toc(DirectTimer);

EventTableDirect = DirectEvents;
hDir = BuildImpulseResponseFromEvents(EventTableDirect, fs, Npoints);
TotalTime = ScatterTime + DirectTime ;

end

function flag = isAzimuthInBeamRangeLocal(phiDeg, Beam)
% isAzimuthInBeamRangeLocal
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

% 全向/全方位直接通过
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
    % 跨越 ±180° 的范围，例如 [170, -170]
    flag = (phi >= az1) || (phi <= az2);
end
end

function ev = makeEmptyBottomEventLocal()
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
ev.NumBotIn  = [] ;
ev.NumTopIn  = [] ;
ev.NumBotOut = [] ;
ev.NumTopOut = [] ;
ev.PathClass =  '';
ev.PathClassID = [] ;
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
        error('SigCalcuBottom:MissingRandomInfo', ...
            'RandomInfo.%s is required.', required{k});
    end
end
end

function z = bottomDepthFromSSPLocal(SSP)
z = NaN;
if isnumeric(SSP) && ~isempty(SSP)
    z = max(double(SSP(:,1)), [], 'omitnan');
end
end
function val = getArrivalFieldValueLocal(S, fieldName, idx, defaultVal)
val = defaultVal;
if isstruct(S) && isfield(S, fieldName)
    tmp = S.(fieldName);
    if numel(tmp) >= idx
        val = tmp(idx);
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

function value = getFieldOrDefaultLocal(S, fieldName, defaultValue)
value = defaultValue;
if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
end
end
