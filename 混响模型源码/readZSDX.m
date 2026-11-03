function result = readZSDX(jsonFile,startTheta,deltaDeg,thetaCount)
%readZSDX 用一个 EXE 进程完成全部阵列指向角遍历。
% 每个工况开始时，EXE 向标准输出打印英文 theta 和中文当前指向角。
% 不生成或更新进度 JSON，也不返回进度文件字段。
% 时变噪声、解析声压和 RL 均由同版 EXE 内部生成；无需外部噪声 helper。
%
% 输入参数：
%   jsonFile   - 基础工况 JSON 文件路径。
%   startTheta - 第一个阵列指向角，单位为度。缺省时读取当前阵型的指向角。
%   deltaDeg   - 相邻工况的指向角增量，单位为度。缺省值为 0。
%   thetaCount - 需要计算的指向角数量。缺省值为 1。
%
% 输出结果：
%   result.arrayType    - 当前阵型编号。
%   result.thetaList    - 每次计算使用的阵列指向角。
%   result.timeRt       - 所有工况共用的时响时间轴（double）。
%   result.yTotal       - 含 SourceLevel 和同一次时变噪声的解析复声压，单位 uPa。
%   result.yDir         - clean 直达声复响应；保持原模型语义与量纲。
%   result.ySca         - clean 散射声复响应；保持原模型语义与量纲。
%   result.RL           - 与 yTotal 同一次噪声 realization 的 50 ms RL。
%   result.PressureInfo - yTotal 的单位、增益与构造方式。
%   result.BTR          - BTR double 数组：扫描角×时间×指向角。
%   result.timeBTR      - BTR 时间轴。
%   result.scanAngles   - BTR 阵轴角 theta，范围 [0,180] 度。
%   result.BTRDisplay   - uPa 解析复声压 double 数组：扫描角×声压时间×指向角。
%                         成功返回后删除 EXE 中转压力 MAT；完整数组需足够内存。
%   result.timeBTRDisplay - BTRDisplay 的高采样率压力时间轴。

%% 1. 检查输入 JSON，并读取基础工况配置

if nargin < 1 || isempty(jsonFile)
    error('readZSDX:MissingJson','jsonFile is required.');
end

jsonFile = char(jsonFile);

if ~isfile(jsonFile)
    error('readZSDX:NotFound','JSON not found: %s',jsonFile);
end

cfg = readJsonUtf8Local(jsonFile);

% 兼容旧 JSON：这些字段已不再是外部输入。内部固定使用同一套面元
% 坐标和共享相位规则，因此在生成单工况 JSON 前主动删除它们。
cfg = removeDeprecatedGridFieldsLocal(cfg);

%% 2. 识别当前阵型及其有效指向角字段

[arrayType,jsonStartTheta,thetaField] = resolveThetaTargetLocal(cfg);
fprintf('[readZSDX] ArrayType=%d, theta target=%s.\n',arrayType,thetaField);

%% 3. 补齐可选参数，并生成本次要计算的全部指向角

if nargin < 2 || isempty(startTheta)
    startTheta = jsonStartTheta;
end

if nargin < 3 || isempty(deltaDeg)
    deltaDeg = 0;
end

if nargin < 4 || isempty(thetaCount)
    thetaCount = 1;
end

validateattributes( ...
    [startTheta deltaDeg thetaCount], ...
    {'numeric'}, ...
    {'real','finite'});

if thetaCount < 1 || fix(thetaCount) ~= thetaCount
    error('readZSDX:ThetaCount', ...
        'thetaCount must be a positive integer.');
end
if arrayType==4 && (thetaCount~=1 || deltaDeg~=0)
    error('readZSDX:CustomBeamSingleCase', ...
        'Beam.ArrayType=4为固定自定义波束，只允许thetaCount=1且deltaDeg=0。');
end

% 例如 startTheta=-30、deltaDeg=5、thetaCount=5 时，
% thetaList 为 [-30 -25 -20 -15 -10]。
thetaList = startTheta + (0:thetaCount-1) * deltaDeg;

%% 4. 定位发布目录、EXE，并建立本轮计算的独立工作目录

thisDir = fileparts(mfilename('fullpath'));
packageRoot = resolvePackageRootLocal(thisDir);
exePath = fullfile(packageRoot,'ZSDXReverb.exe');

% 时间戳用于隔离不同批次，避免覆盖以前的工况结果。
runId = [ ...
    'readZSDX_' ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) ...
    ];
runRoot = fullfile(packageRoot,'work','runs',runId);
mkdir(runRoot);

%% 5. 预分配批量结果容器

timeAxis = [];
yRows = cell(thetaCount,1);
yDirRows = cell(thetaCount,1);
yScaRows = cell(thetaCount,1);
BTRPages = cell(thetaCount,1);
pressureRows=cell(thetaCount,1);rlRows=cell(thetaCount,1);voltageRows=cell(thetaCount,1);
PressureInfo=[];
BTRDisplayFiles = cell(thetaCount,1);
timeBTR = [];
scanAngles = [];

requestedSaveSelection = unique(double(cfg.Output.saveSelection(:).'));
if isempty(requestedSaveSelection), requestedSaveSelection = 0; end
if any(~ismember(requestedSaveSelection,0:5))
    error('readZSDX:InvalidOutputSelection', ...
        'Output.saveSelection values must be 0..5.');
end
if numel(requestedSaveSelection)>1
    requestedSaveSelection(requestedSaveSelection==0)=[];
end
savedOutputDir = fullfile(runRoot,'saved_outputs');

%% 6. 写入一个内部批处理 JSON，并只启动一次 EXE

% readZSDX 专用字段不出现在用户示例 JSON 中。EXE 在同一进程中按
% thetaList 顺序运行，每个角度仍建立独立配置、输出目录和 BELLHOP
% 临时目录；因此声线追踪会按新的主波束覆盖范围完整重算。
batchCfg = cfg;
batchCfg.Output.saveSelection = 0;
batchCfg.Runtime.ReturnToCaller = true;
if any(ismember(requestedSaveSelection,[4 5]))
    batchCfg.BTR.enable = true;
end
batchCfg = rewritePathsLocal(batchCfg,packageRoot);
batchCfg.File.outputPath = slashLocal(fullfile(runRoot,'batch_output'));
batchCfg.Runtime.TempWorkDir = slashLocal(fullfile(runRoot,'batch_temp'));
batchCfg.Runtime.ThetaBatch = struct( ...
    'thetaList',thetaList, ...
    'runRoot',slashLocal(runRoot), ...
    'runId',runId);

batchJson = fullfile(runRoot,'batch_readZSDX.json');
writeJsonUtf8Local(batchJson,batchCfg);
stdoutLog = fullfile(runRoot,'stdout.log');
fprintf(['[readZSDX] Starting one EXE for %d theta case(s). ' ...
    'The scatter parallel pool will be created once and reused.\n'],thetaCount);
cmd = sprintf('cmd /d /c ""%s" "%s" 2>&1"',exePath,batchJson);
[exitCode,cmdOutput] = system(cmd,'-echo');
writeTextUtf8Local(stdoutLog,cmdOutput);

if exitCode ~= 0
    error('readZSDX:ExeFailed', ...
        'Theta-batch EXE failed (code %d). Log: %s',exitCode,stdoutLog);
end

batchResultFile = fullfile(runRoot,'BatchCallResult.json');
if ~isfile(batchResultFile)
    error('readZSDX:NoBatchResult','Missing %s.',batchResultFile);
end
batchResult = readJsonUtf8Local(batchResultFile);
if ~logical(batchResult.ok) || double(batchResult.caseCount)~=thetaCount
    error('readZSDX:BatchFailed','EXE theta batch did not complete all cases.');
end

%% 7. 逐个读取同一 EXE 生成的结果缓存

for k = 1:thetaCount
    caseDir = fullfile(runRoot,sprintf('theta_%04d',k));
    outDir = fullfile(caseDir,'output');
    summaryFile = fullfile(outDir,'RunSummary.json');
    if ~isfile(summaryFile)
        error('readZSDX:NoSummary','Missing %s.',summaryFile);
    end
    status = readJsonUtf8Local(summaryFile);
    if ~logical(status.ok)
        error('readZSDX:RunFailed', ...
            'RunSummary.ok = false for theta = %g.',thetaList(k));
    end

    fprintf( ...
        ['[readZSDX] Completed theta = %g deg: channels=%d, ' ...
         'BELLHOP=%d/%d, mainBeam=%s, elevSide=%s/%s dB, ' ...
         'azMain=%s, azSide=%s/%s dB, poolStartedNow=%d, poolReused=%d.\n'], ...
        thetaList(k),status.frequencyChannelCount, ...
        status.bellhopJobCountActual,status.bellhopJobCountExpected, ...
        mat2str(status.beamResolved.MainBeam), ...
        mat2str(status.beamResolved.SideRange), ...
        mat2str(status.beamResolved.SideDown_dB), ...
        mat2str(status.beamResolved.AzimuthRange), ...
        mat2str(status.beamResolved.AzimuthSideRange), ...
        mat2str(status.beamResolved.AzimuthSideDown_dB), ...
        logical(status.scatterParallel.StartedNow), ...
        logical(status.scatterParallel.ReusedExistingPool));

    returnFile = fullfile(outDir,'RuntimeReturn.tmp');
    returned = readRuntimeReturnLocal(returnFile);
    if any(~isfinite(returned.yDir(:))) || ...
            any(~isfinite(returned.ySca(:))) || ...
            any(~isfinite(returned.yTotal(:)))
        error('readZSDX:NonfiniteModelResponse', ...
            ['EXE returned nonfinite time-domain samples for theta = %g. ', ...
             'Inspect %s and the retained RuntimeReturn.tmp; do not use RL/BTR from this run.'], ...
            thetaList(k),summaryFile);
    end
    delete(returnFile);
    tk = returned.timeRt;

    if isempty(timeAxis)
        timeAxis = tk;
    elseif numel(tk) ~= numel(timeAxis) || max(abs(tk-timeAxis)) > 1e-9
        error('readZSDX:TimeMismatch','Time axes differ between runs.');
    end

    pressureRows{k}=returned.Pressure;
    rlRows{k}=returned.RL;
    voltageRows{k}=returned.Voltage;
    if k==1,PressureInfo=status.pressureInfo;
    elseif ~isequaln(PressureInfo,status.pressureInfo)
        error('readZSDX:PressureCalibrationMismatch','Pressure calibration differs across theta cases.');
    end
    yRows{k} = returned.yTotal;
    yDirRows{k} = returned.yDir;
    yScaRows{k} = returned.ySca;
    BTRPages{k} = returned.BTR;
    candidateDisplayFile=fullfile(outDir,'BTRDisplay.mat');
    if isfield(status,'btrDisplay') && isstruct(status.btrDisplay) && ...
            isfield(status.btrDisplay,'File') && ~isempty(status.btrDisplay.File)
        if ~isfile(candidateDisplayFile)
            error('readZSDX:MissingBTRDisplay','Missing %s.',candidateDisplayFile);
        end
        BTRDisplayFiles{k}=candidateDisplayFile;
    end

    if isempty(timeBTR)
        timeBTR = returned.timeBTR;
        scanAngles = returned.scanAngles;
    elseif ~isempty(returned.timeBTR)
        if ~isequal(size(returned.timeBTR),size(timeBTR)) || ...
                max(abs(returned.timeBTR-timeBTR))>1e-9 || ...
                ~isequal(size(returned.scanAngles),size(scanAngles)) || ...
                max(abs(returned.scanAngles-scanAngles))>1e-9
            error('readZSDX:BTRAxisMismatch','BTR axes differ between runs.');
        end
    end
end

%% 8. 将各指向角的复时域结果拼成二维矩阵

% yTotal 的每一行对应 thetaList 中的一个指向角。
yTotal = complex(zeros(thetaCount,numel(timeAxis)));
yDir = complex(zeros(thetaCount,numel(timeAxis)));
ySca = complex(zeros(thetaCount,numel(timeAxis)));

for k = 1:thetaCount
    yTotal(k,:) = yRows{k}(:).';
    yDir(k,:) = yDirRows{k}(:).';
    ySca(k,:) = yScaRows{k}(:).';
end

% EXE supplies one immutable pressure/voltage/noise realization per theta case.
pDisplay=vertcat(pressureRows{:});
RLDisplay=vertcat(rlRows{:});
vTotalNoisy=vertcat(voltageRows{:});
if ~isequal(size(pDisplay),[thetaCount,numel(timeAxis)]) || ...
        ~isequal(size(RLDisplay),size(pDisplay)) || ...
        ~isequal(size(vTotalNoisy),size(pDisplay)) || ...
        any(~isfinite(pDisplay(:))) || any(~isfinite(RLDisplay(:))) || ...
        any(~isfinite(vTotalNoisy(:)))
    error('readZSDX:InvalidPublicDisplay','EXE public display arrays have invalid shape or values.');
end
% NoiseAudit remains in RunSummary; never return result.NoiseInfo.

BTR = packBTRPagesLocal(BTRPages);
BTRDisplay=[];
timeBTRDisplay=[];
if any(~cellfun(@isempty,BTRDisplayFiles))
    if any(cellfun(@isempty,BTRDisplayFiles))
        error('readZSDX:BTRDisplayMissingCase', ...
            'BTRDisplay is missing for one or more theta runs.');
    end
    for k=1:thetaCount
        displayStore=matfile(BTRDisplayFiles{k});
        caseTime=double(displayStore.timeBTRDisplay);
        caseAngles=double(displayStore.scanAngles);
        if k==1
            timeBTRDisplay=caseTime(:).';
            BTRDisplay=complex(zeros(numel(scanAngles), ...
                numel(timeBTRDisplay),thetaCount,'double'));
        end
        if ~isequal(caseTime(:).',timeBTRDisplay) || ...
                ~isequal(caseAngles(:).',scanAngles(:).') || ...
                ~isequal(size(displayStore,'BTRDisplay'), ...
                    [numel(scanAngles),numel(timeBTRDisplay)])
            error('readZSDX:BTRDisplayGridMismatch', ...
                'BTRDisplay axes or dimensions differ between theta runs.');
        end
        casePressure=displayStore.BTRDisplay;
        if any(~isfinite(casePressure(:)))
            error('readZSDX:BTRDisplayNonFinite', ...
                'BTRDisplay pressure contains non-finite values.');
        end
        BTRDisplay(:,:,k)=double(casePressure);
        clear displayStore casePressure
    end
end

saveSelectedOutputsLocal(savedOutputDir,requestedSaveSelection, ...
    timeAxis,vTotalNoisy,BTR,timeBTR,scanAngles,thetaList);

%% 9. 仅返回调用方需要的数值结果

result = struct( ...
    'arrayType',arrayType, ...
    'thetaList',thetaList, ...
    'timeRt',timeAxis(:).', ...
    'yTotal',pDisplay, ...
    'yDir',yDir, ...
    'ySca',ySca, ...
    'RL',RLDisplay, ...
    'PressureInfo',PressureInfo, ...
    'BTR',BTR, ...
    'timeBTR',timeBTR(:).', ...
    'scanAngles',scanAngles(:).', ...
    'BTRDisplay',BTRDisplay, ...
    'timeBTRDisplay',timeBTRDisplay(:).');

% EXE 与 wrapper 间的中转缓存已经读入结果；异常时保留缓存用于诊断。
for k=1:thetaCount
    if ~isempty(BTRDisplayFiles{k})
        delete(BTRDisplayFiles{k});
    end
end

end

function [arrayType,startTheta,fieldPath] = resolveThetaTargetLocal(cfg)
if ~isfield(cfg,'Beam') || ~isstruct(cfg.Beam) || ...
        ~isfield(cfg.Beam,'ArrayType')
    error('readZSDX:ArrayType','Missing Beam.ArrayType.');
end
arrayType=double(cfg.Beam.ArrayType);
switch arrayType
    case 1
        startTheta=requiredNestedAngleLocal(cfg.Beam,'verticalArray','thetaDeg');
        fieldPath='Beam.verticalArray.thetaDeg';
    case 2
        % The effective steering angle of the horizontal line array is its
        % azimuth phiDeg; the external theta argument is mapped to it.
        startTheta=requiredNestedAngleLocal(cfg.Beam,'horiArray','phiDeg');
        fieldPath='Beam.horiArray.phiDeg';
    case 3
        startTheta=requiredNestedAngleLocal(cfg.Beam,'cylinArray','thetaDeg');
        fieldPath='Beam.cylinArray.thetaDeg';
    case 4
        startTheta=0;
        fieldPath='Beam.customMainBeam（固定，不改写角度）';
    otherwise
        error('readZSDX:ArrayType', ...
            'Beam.ArrayType必须为1、2、3或4。');
end
end

function value = requiredNestedAngleLocal(beam,sectionName,fieldName)
if ~isfield(beam,sectionName) || ~isstruct(beam.(sectionName)) || ...
        ~isfield(beam.(sectionName),fieldName)
    error('readZSDX:MissingThetaField', ...
        'Missing Beam.%s.%s.',sectionName,fieldName);
end
value=double(beam.(sectionName).(fieldName));
validateattributes(value,{'numeric'},{'scalar','real','finite'});
end

function cfg = removeDeprecatedGridFieldsLocal(cfg)
%removeDeprecatedGridFieldsLocal 删除旧版中不再对外开放的网格控制字段。

if ~isfield(cfg,'Computation') || ~isstruct(cfg.Computation)
    return;
end

deprecatedFields = {'RandomSeed','ScatterGrid','Itg','frequencyChannelMode'};

for k = 1:numel(deprecatedFields)
    fieldName = deprecatedFields{k};

    if isfield(cfg.Computation,fieldName)
        cfg.Computation = rmfield(cfg.Computation,fieldName);
    end
end

end

function data = readRuntimeReturnLocal(fileName)
% Read the short-lived EXE-to-MATLAB numeric return cache.
if ~isfile(fileName)
    error('readZSDX:MissingReturnCache', ...
        'Missing runtime return cache: %s',fileName);
end
fid=fopen(fileName,'r','ieee-le');
if fid<0
    error('readZSDX:OpenReturnCache','Cannot open %s.',fileName);
end
cleanup=onCleanup(@() fclose(fid)); 
magic=char(fread(fid,[1 8],'*uint8'));
if ~strcmp(magic,'ZSDXRET1')
    error('readZSDX:ReturnCacheMagic','Invalid runtime return cache.');
end
version=fread(fid,1,'uint32=>double');
if version~=3
    error('readZSDX:ReturnCacheVersion', ...
        'Expected same-package return cache version 3; received %g. Replace readZSDX.m and EXE together.',version);
end
dims=fread(fid,3,'uint64=>double');
if numel(dims)~=3
    error('readZSDX:ReturnCacheHeader','Incomplete return cache header.');
end
nTime=dims(1); nBtrTime=dims(2); nAngles=dims(3);
data=struct();
data.timeRt=readRealLocal(fid,nTime).';
data.yTotal=readComplexLocal(fid,nTime).';
data.yDir=readComplexLocal(fid,nTime).';
data.ySca=readComplexLocal(fid,nTime).';
data.timeBTR=readRealLocal(fid,nBtrTime).';
data.scanAngles=readRealLocal(fid,nAngles).';
data.BTR=reshape(readRealLocal(fid,nAngles*nBtrTime),nAngles,nBtrTime);
data.Pressure=readComplexLocal(fid,nTime).';
data.RL=readRealLocal(fid,nTime).';
data.Voltage=readRealLocal(fid,nTime).';
if ~isempty(fread(fid,1,'*uint8'))
    error('readZSDX:ReturnCacheTrailingBytes','Unexpected return cache payload.');
end
end

function value=readRealLocal(fid,n)
value=fread(fid,n,'double=>double');
if numel(value)~=n
    error('readZSDX:ReturnCacheEOF', ...
        'Unexpected end of runtime return cache.');
end
end

function value=readComplexLocal(fid,n)
realPart=readRealLocal(fid,n);
imagPart=readRealLocal(fid,n);
value=complex(realPart,imagPart);
end

function pages=packBTRPagesLocal(values)
if all(cellfun(@isempty,values))
    pages=[];
    return;
end
if any(cellfun(@isempty,values))
    error('readZSDX:BTRMissingPage', ...
        'BTR is missing for one or more theta runs.');
end
baseSize=size(values{1});
for k=2:numel(values)
    if ~isequal(size(values{k}),baseSize)
        error('readZSDX:BTRSizeMismatch', ...
            'BTR sizes differ between theta runs.');
    end
end
pages=cat(3,values{:});
end

function saveSelectedOutputsLocal(outDir,selection,timeRt,vTotalNoisy,BTR,timeBTR,scanAngles,thetaDeg)
% 0: no product; 1: time FIG; 2: time BIN; 3: time MAT;
% 4: BTR FIG; 5: BTR MAT.
selection=selection(selection~=0);
if isempty(selection), return; end
if ~exist(outDir,'dir'), mkdir(outDir); end

if ismember(1,selection)
    f=figure('Visible','off');
    peak=max(abs(vTotalNoisy(:)));
    for i=1:size(vTotalNoisy,1)
        subplot(size(vTotalNoisy,1),1,i);
        plot(timeRt,vTotalNoisy(i,:)); grid on;
        xlim([timeRt(1) timeRt(end)]);
        if peak>0, ylim([-peak peak]); end
        ylabel('接收端电压 (V)');
        legend(sprintf('theta=%g deg，含时变噪声',thetaDeg(i)), ...
            'Location','best');
        if i==1
            title('ZSDX 含时变噪声时域响应（已考虑 SL、接收灵敏度和放大增益）');
        end
        if i==size(vTotalNoisy,1), xlabel('Time / s'); end
    end
    savefig(f,fullfile(outDir,'TimeResponse.fig')); close(f);
end

if ismember(2,selection)
    writeTimeBinLocal(fullfile(outDir,'TimeResponse.bin'),timeRt,vTotalNoisy);
end

if ismember(3,selection)
    thetaList=double(thetaDeg(:).'); %#ok<NASGU>
    Units='V'; %#ok<NASGU>
    PayloadKind='noisy_receiver_voltage'; %#ok<NASGU>
    PayloadVersion='V4_20261004'; %#ok<NASGU>
    matrixOrientation='rows=thetaList, columns=timeRt'; %#ok<NASGU>
    save(fullfile(outDir,'TimeResponse.mat'),'timeRt','vTotalNoisy', ...
        'thetaList','Units','PayloadKind','PayloadVersion', ...
        'matrixOrientation','-v7.3');
end

if any(ismember(selection,[4 5])) && isempty(BTR)
    error('readZSDX:MissingBTR', ...
        'BTR output was selected but BTR is empty.');
end

if ismember(4,selection)
    f=figure('Visible','off');
    for i=1:size(BTR,3)
        ax=subplot(size(BTR,3),1,i);
        BTRDisplay=double(BTR(:,:,i));
        finiteValues=BTRDisplay(isfinite(BTRDisplay));
        if isempty(finiteValues)
            BTRDisplay=-50*ones(size(BTRDisplay));
        else
            BTRDisplay=BTRDisplay-max(finiteValues);
            BTRDisplay(~isfinite(BTRDisplay))=-50;
            BTRDisplay=max(-50,min(0,BTRDisplay));
        end
        img=imagesc(ax,scanAngles,timeBTR,BTRDisplay.'); axis(ax,'xy');
        img.UserData=struct('Schema','ReverbBTRFigureV3', ...
            'RawBTR',BTR(:,:,page),'timeBTR',timeBTR, ...
            'scanAngles',scanAngles, ...
            'AngleConvention','theta_0_180_array_axis_deg', ...
            'RawScale','dB','MatrixLayout','angle_by_time', ...
            'DisplayMatrixLayout','time_by_angle');
        colormap(ax,jet(256)); clim(ax,[-50 0]);
        colorbar; ylabel('Time / s');
        title(sprintf('Beam-Time Response, theta=%g deg',thetaDeg(i)));
        if i==size(BTR,3), xlabel('Array-axis angle theta / deg'); end
    end
    savefig(f,fullfile(outDir,'BTR.fig')); close(f);
end

if ismember(5,selection)
    matrixOrientation='rows=scanAngles, columns=timeBTR, pages=thetaDeg'; %#ok<NASGU>
    AngleConvention='theta_0_180_array_axis_deg'; %#ok<NASGU>
    save(fullfile(outDir,'BTR.mat'), ...
        'BTR','timeBTR','scanAngles','thetaDeg','AngleConvention','matrixOrientation','-v7.3');
end
end

function writeTimeBinLocal(fileName,timeRt,vTotalNoisy)
% Logical complex matrix is [timeRt; vTotalNoisy], i.e. thetaCount+1 rows.
% Each complex element is stored as two little-endian doubles: real, imag.
fid=fopen(fileName,'w','ieee-le');
if fid<0, error('readZSDX:WriteBin','Cannot write %s.',fileName); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
payload=[double(timeRt(:)).';double(vTotalNoisy)];
interleaved=[real(payload(:)).';imag(payload(:)).'];
fwrite(fid,interleaved,'double');
end

function root = resolvePackageRootLocal(startDir)
%resolvePackageRootLocal 从 readZSDX.m 所在位置寻找发布包根目录。
%
% 允许 readZSDX.m 位于发布根目录、package 子目录、build/package
% 上层工作区等常见位置；找到 ZSDXReverb.exe 后即停止搜索。

candidates = { ...
    startDir, ...
    fullfile(startDir,'package'), ...
    fullfile(startDir,'build','package'), ...
    fullfile(startDir,'..','..') ...
    };

root = '';

for k = 1:numel(candidates)
    p = char(java.io.File(candidates{k}).getCanonicalPath());

    if isfile(fullfile(p,'ZSDXReverb.exe'))
        root = p;
        break;
    end
end

if isempty(root)
    error('readZSDX:NoExe', ...
        'Cannot locate ZSDXReverb.exe from %s.',startDir);
end

end

function cfg = rewritePathsLocal(cfg,root)
%rewritePathsLocal 将可随发布包携带的资源改写为绝对路径。
%
% 这里只改写能够在 package/env 或 package/signals 中找到的同名文件；
% 找不到时保留 JSON 原值，让 EXE 按原配置继续校验并报告问题。

if isfield(cfg,'Environment') && ...
        isfield(cfg.Environment,'sspPath')

    [~,name,ext] = fileparts(char(cfg.Environment.sspPath));
    candidate = fullfile(root,'env',[name ext]);

    if isfile(candidate)
        cfg.Environment.sspPath = slashLocal(candidate);
    end
end

if isfield(cfg,'Signal') && ...
        isfield(cfg.Signal,'customPath') && ...
        ~isempty(cfg.Signal.customPath)

    [~,name,ext] = fileparts(char(cfg.Signal.customPath));
    candidate = fullfile(root,'signals',[name ext]);

    if isfile(candidate)
        cfg.Signal.customPath = slashLocal(candidate);
    end
end

end

function p = slashLocal(p)
%slashLocal 把 Windows 反斜杠改为 JSON 中更稳定的正斜杠形式。

p = strrep(char(p),'\','/');

end

function value = readJsonUtf8Local(fileName)
%readJsonUtf8Local 读取不带 BOM 的 UTF-8 JSON 文件。

fid = fopen(fileName,'r');

if fid < 0
    error('readZSDX:OpenJson','Cannot open %s.',fileName);
end

cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid,inf,'*uint8').';

% 明确拒绝 UTF-8 BOM，避免不同启动方式对文件头处理不一致。
if numel(bytes) >= 3 && ...
        isequal(bytes(1:3),uint8([239 187 191]))
    error('readZSDX:JsonBom', ...
        'JSON must be UTF-8 without BOM: %s',fileName);
end

value = jsondecode(native2unicode(bytes,'UTF-8'));

end

function writeJsonUtf8Local(fileName,value)
%writeJsonUtf8Local 以无 BOM UTF-8 格式写出便于审计的 JSON。

folder = fileparts(fileName);

if ~isempty(folder) && ~exist(folder,'dir')
    mkdir(folder);
end

% 新版 MATLAB 支持 PrettyPrint；若环境不支持则退回普通 JSON。
try
    text = jsonencode(value,'PrettyPrint',true);
catch
    text = jsonencode(value);
end

fid = fopen(fileName,'w','n','UTF-8');

if fid < 0
    error('readZSDX:WriteJson','Cannot write %s.',fileName);
end

cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s',text);

end

function writeTextUtf8Local(fileName,text)
%writeTextUtf8Local 保存 EXE 命令行输出，便于事后检查运行过程。

fid = fopen(fileName,'w','n','UTF-8');

if fid < 0
    error('readZSDX:WriteLog','Cannot write %s.',fileName);
end

cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s',text);

end

