function [TotalTime, hSca, hDir, EventTableBottom, EventTableSurface, EventTableDirect] = ImpulseResponse(InputParams, OptionBorder, TempWorkDir, SaveEvents, varargin)
% ImpulseResponse
% 保留相位信息的界面混响冲激响应计算封装函数。
%
% 接口：
%   [hSca, hDir, EventTableBottom, EventTableSurface, EventTableDirect] = ...
%       ImpulseResponse(InputParams, OptionBorder, TempWorkDir, SaveEvents)
%
% 输入：
%   InputParams  : 模型输入参数结构体
%   OptionBorder : 0 = 海底 + 海面；1 = 仅海底
%   TempWorkDir  : RunReverbSimulation 创建的共享临时目录
%   SaveEvents   : false = 只生成 h(t)，不保存事件表，用于耗时指标
%                  true  = 保存事件表，用于 BTR / SPDR / 阵元重构
%
% 输出：
%   hSca              : 总散射冲激响应，hBottom + hSurf
%   hDir              : 直达波冲激响应
%   EventTableBottom  : 海底散射事件表；SaveEvents=false 时为空
%   EventTableSurface : 海面散射事件表；SaveEvents=false 或仅海底时为空
%   EventTableDirect  : 直达波事件表；SaveEvents=false 时为空

% 新的自动频率入口使用第五个参数 'multi_channel'。此时前两个输出
% 分别为 ChannelResults 和传播/共享网格诊断信息；旧四参数接口保留。
if ~isempty(varargin) && strcmpi(string(varargin{1}),'multi_channel')
    [TotalTime,hSca]=ImpulseResponseChannels(InputParams,OptionBorder,TempWorkDir,SaveEvents);
    hDir=[]; EventTableBottom=[]; EventTableSurface=[]; EventTableDirect=[];
    return;
end

if nargin < 3 || isempty(OptionBorder)
    OptionBorder = 1;
end
if nargin < 4 || isempty(TempWorkDir)
    TempWorkDir = getFieldOrDefaultLocal(InputParams, 'TempWorkDir', '');
end
if nargin < 4 || isempty(SaveEvents)
    SaveEvents = false;
end
SaveEvents = logical(SaveEvents);

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
Rmax = getFieldOrDefaultLocal(InputParams, 'Rmax', 60000);
Sediment = InputParams.Sediment;
Tht = getFieldOrDefaultLocal(InputParams, 'Tht', deg2rad(9));
Miu = 10^(getFieldOrDefaultLocal(InputParams, 'Miu', -32) / 10);
v = 10^(getFieldOrDefaultLocal(InputParams, 'v', -10) / 10);

f0 = getFieldOrDefaultLocal(InputParams, 'f0', getFieldOrDefaultLocal(InputParams, 'f0', 500));
fs = InputParams.fs;
itg = getFieldOrDefaultLocal(InputParams, 'Itg', 0.02);
U = getFieldOrDefaultLocal(InputParams, 'U', 0);
SSP = InputParams.SSP;

Beam = getFieldOrDefaultLocal(InputParams, 'Beam', getDefaultBeamLocal());
Beam = normalizeBeamLocal(Beam);

% 优先使用 TWindowCompute；否则使用 TWindow；默认 50 s。
TWindow = getFieldOrDefaultLocal(InputParams, 'TWindowCompute', ...
          getFieldOrDefaultLocal(InputParams, 'TWindow', 50));
Rmax = getFieldOrDefaultLocal(InputParams, 'Rmax', 60000);

OriginalDir = getFieldOrDefaultLocal(InputParams, 'OriginalDir', pwd);

% -------------------------
% 2. 海底冲激响应
% -------------------------
if SaveEvents
    [TotalTime , hBottom, hDir, EventTableBottom, EventTableDirect] = SigCalcuBottom( ...
        Rd, Sd, RecvRange, Sediment, Tht, Miu, v, f0, fs, itg, ...
        TempWorkDir, SSP, OriginalDir, Beam, TWindow, Rmax, SaveEvents);
    % TotalTime = [];
else
    [TotalTime, hBottom, hDir] = SigCalcuBottom( ...
        Rd, Sd, RecvRange, Sediment, Tht, Miu, v, f0, fs, itg, ...
        TempWorkDir, SSP, OriginalDir, Beam, TWindow, Rmax, SaveEvents);
    EventTableBottom = [];
    EventTableDirect = [];
end



% -------------------------
% 3. 海面冲激响应，可选
% -------------------------
hSurf = zeros(size(hBottom));
EventTableSurface = [];

SurfaceSpreadInfo = struct('Enabled', false, 'Reason', 'not called');

if OptionBorder == 0
    if SaveEvents
        [SurfTime, hSurf, EventTableSurface] = SigCalcuSurface( ...
            Rd, Sd, RecvRange, Sediment, U, f0, fs, itg, ...
            TempWorkDir, SSP, OriginalDir, Beam, TWindow, Rmax, SaveEvents);
    else
        [SurfTime, hSurf] = SigCalcuSurface( ...
            Rd, Sd, RecvRange, Sediment, U, f0, fs, itg, ...
            TempWorkDir, SSP, OriginalDir, Beam, TWindow, Rmax, SaveEvents);
    end

    TotalTime = TotalTime + SurfTime;

    if isfield(InputParams, 'EnableSurfaceDynamic') && logical(InputParams.EnableSurfaceDynamic)
        [hSurf, SurfaceSpreadInfo] = ApplySurfaceDynamicSpread(hSurf, fs, U, InputParams);
    end
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
    Beam.SideDown_dB = [0 0];
    Beam.ElevSideDown_dB = [0 0];
    Beam.AzimuthSideRange = [-180 -180; 180 180];
    Beam.AzimuthSideDown_dB = [0 0];
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
