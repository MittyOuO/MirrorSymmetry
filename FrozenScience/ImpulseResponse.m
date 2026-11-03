function [TotalTime, hSca, hDir, EventTableBottom, EventTableSurface, ...
        EventTableDirect, RandomInfo, G3Audit, BottomGridAudit] = ImpulseResponse( ...
        InputParams, OptionBorder, TempWorkDir, varargin)
% ImpulseResponse
% 单次事件实现的界面混响冲激响应计算封装函数。
%
% 接口：
%   [TotalTime,hSca,hDir,EventTableBottom,EventTableSurface, ...
%       EventTableDirect,RandomInfo] = ...
%       ImpulseResponse(InputParams,OptionBorder,TempWorkDir)
%
% 输入：
%   InputParams  : 模型输入参数结构体
%   OptionBorder : 0 = 海底 + 海面；1 = 仅海底
%   TempWorkDir  : RunReverbSimulation 创建的共享临时目录
% 输出：
%   hSca              : 总散射冲激响应，hBottom + hSurf
%   hDir              : 直达波冲激响应
%   EventTable*        : 与 h(t) 同一次生成的完整事件表
%   RandomInfo         : 本次运行唯一 seedUsed 和随机模型元数据

if nargin < 2 || isempty(OptionBorder)
    OptionBorder = 1;
end
if nargin < 3 || isempty(TempWorkDir)
    TempWorkDir = getFieldOrDefaultLocal(InputParams, 'TempWorkDir', '');
end

if ~isempty(varargin) && islogical(varargin{1})
    error('ImpulseResponse:SaveEventsRemoved', ...
        'SaveEvents has been removed. Event tables are always generated.');
end

[InputParams, RandomInfo] = ResolveRandomRealization(InputParams);
[InputParams, ~, G3Audit] = ResolveG3Parameters(InputParams,'single');
BottomGridAudit=[];

% 自动频率入口使用第四个参数 'multi_channel'。此时前两个输出分别为
% ChannelResults 和传播/共享网格诊断信息。
if ~isempty(varargin) && strcmpi(string(varargin{1}),'multi_channel')
    [TotalTime,hSca]=ImpulseResponseChannels(InputParams,OptionBorder,TempWorkDir);
    hDir=[]; EventTableBottom=[]; EventTableSurface=[]; EventTableDirect=[];
    return;
end

if isempty(TempWorkDir)
    error('ImpulseResponse:MissingTempWorkDir', 'TempWorkDir 不能为空。');
end
if ~exist(TempWorkDir, 'dir')
    mkdir(TempWorkDir);
end

% -------------------------
% 1. 解析 InputParams
% -------------------------
Rd = InputParams.Rd;
Sd = InputParams.Sd;
RecvRange = InputParams.RecvRange;
if RecvRange == 0
    RecvRange = 1;
end
Rmax = InputParams.DomainResolved.RmaxM;
Sediment = InputParams.Sediment;
Tht = InputParams.ScatteringResolved.ThtRad;
Miu = InputParams.ScatteringResolved.MiuLinear;
v = InputParams.ScatteringResolved.vLinear;

f0 = getFieldOrDefaultLocal(InputParams, 'f0', getFieldOrDefaultLocal(InputParams, 'f0', 500));
fs = InputParams.fs;
itg = getFieldOrDefaultLocal(InputParams, 'Itg', 0.02);
U = getFieldOrDefaultLocal(InputParams, 'U', 0);
SSP = InputParams.SSP;

Beam = getFieldOrDefaultLocal(InputParams, 'Beam', getDefaultBeamLocal());
Beam = normalizeBeamLocal(Beam);

% 优先使用 TWindowCompute；否则使用 TWindow；默认 50 s。
TWindow = getFieldOrDefaultLocal(InputParams, 'TWindowCompute', InputParams.TWindow);

OriginalDir = getFieldOrDefaultLocal(InputParams, 'OriginalDir', pwd);

% -------------------------
% 2. 海底/直达事件与冲激响应（同一次实现）
% -------------------------
[TotalTime, hBottom, hDir, EventTableBottom, EventTableDirect, BottomGridAudit] = SigCalcuBottom( ...
    Rd, Sd, RecvRange, Sediment, Tht, Miu, v, f0, fs, itg, ...
    TempWorkDir, SSP, OriginalDir, Beam, TWindow, Rmax, RandomInfo,InputParams);



% -------------------------
% 3. 海面冲激响应，可选
% -------------------------
hSurf = zeros(size(hBottom));
EventTableSurface = [];

if OptionBorder == 0
    [SurfTime, hSurf, EventTableSurface] = SigCalcuSurface( ...
        Rd, Sd, RecvRange, Sediment, U, f0, fs, itg, ...
        TempWorkDir, SSP, OriginalDir, Beam, TWindow, Rmax, RandomInfo);

    TotalTime = TotalTime + SurfTime;
end

% -------------------------
% 4. 汇总散射响应
% -------------------------
hSca = hBottom + hSurf;

end

% ========================================================================
% Local helper functions
% ========================================================================
function Beam = getDefaultBeamLocal()
    Beam = struct();
    Beam.OpenAngle = [90, -90];
    Beam.MainBeam = Beam.OpenAngle;
    Beam.AzimuthRange = [-180, 180];
    Beam.SideRange = [-90 -90; 90 90];
    Beam.SideDown_dB = 0;
end

function Beam = normalizeBeamLocal(Beam)
    def = getDefaultBeamLocal();
    fields = fieldnames(def);
    for k = 1:numel(fields)
        f = fields{k};
        if ~isfield(Beam, f) || isempty(Beam.(f))
            Beam.(f) = def.(f);
        end
    end
    Beam.OpenAngle = normalizeRange2Local(Beam.OpenAngle, [90 -90]);
    Beam.MainBeam = normalizeRange2Local(Beam.MainBeam, Beam.OpenAngle);
    Beam.AzimuthRange = normalizeAzRangeLocal(Beam.AzimuthRange);
end

function r = normalizeRange2Local(r, defaultVal)
    if isempty(r) || numel(r) < 2
        r = defaultVal;
        return;
    end
    r = double(r(:).');
    r = r(1:2);
    r = [max(r), min(r)];
end

function r = normalizeAzRangeLocal(r)
    if isempty(r) || numel(r) < 2
        r = [-180, 180];
        return;
    end
    r = double(r(:).');
    r = r(1:2);
end

function val = getFieldOrDefaultLocal(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        val = S.(fieldName);
    else
        val = defaultVal;
    end
end
