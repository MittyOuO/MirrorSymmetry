function [EnvAudit] = ResetEnvBottom( f0, Sd, Rd, Sediment, TempWorkDir, sspData, Beam, PropagationSpec, waterDepth)
%ResetEnvBottom Write three bottom .env files from an explicit writer spec.
% All range formulas, alignment, formal/legacy selection, and indexing are
% resolved upstream. This function never infers a mode from input shape.

if nargin < 8
    error('G3:ExplicitPropagationSpecRequired', ...
        'ResetEnvBottom requires a completed PrepareBottomPropagationSpec result.');
end
validateattributes(PropagationSpec,{'struct'},{'scalar'},mfilename,'PropagationSpec');
if ~isfield(PropagationSpec,'ExplicitlyResolved') || ...
        ~isequal(PropagationSpec.ExplicitlyResolved,true)
    error('G3:ExplicitPropagationSpecRequired', ...
        'ResetEnvBottom requires a completed PrepareBottomPropagationSpec result.');
end
if nargin < 9 || isempty(waterDepth), waterDepth = max(sspData(:,1)); end
required={'SourceToBottom','BottomToReceiver','SourceToReceiver','LaunchAngleStepDeg'};
for k=1:numel(required)
    if ~isfield(PropagationSpec,required{k})
        error('G3:IncompletePropagationSpec','Missing PropagationSpec.%s.',required{k});
    end
end
stoBSpec = validateWriterSpecLocal(PropagationSpec.SourceToBottom,'StoB');
btoRSpec = validateWriterSpecLocal(PropagationSpec.BottomToReceiver,'BtoR');
stoRSpec = validateWriterSpecLocal(PropagationSpec.SourceToReceiver,'StoR');
angleStepDeg = double(PropagationSpec.LaunchAngleStepDeg);
safetyMargin = max(100, 0.05*double(waterDepth));
zBox = ceil(max(max(sspData(:,1)),double(waterDepth)) + safetyMargin);

TopOpt = Sediment.TopOpt;
BotOpt =  Sediment.BotOpt;
rmsB =  Sediment.rmsB ;
cB =  Sediment.cB;
cBs =  Sediment.cBs;
rhoB =  Sediment.rhoB;
alphaB =  Sediment.alphaB;
alphaBs =  Sediment.alphaBs;


%% 1. 数据准备
SSP = struct;
SSP.NMedia = 1;
SSP.raw = struct;

% 从传入的 N x 2 矩阵提取深度和声速，补齐密度和衰减
SSP.raw(1).z = sspData(:, 1);
SSP.raw(1).Speed = sspData(:, 2);
SSP.raw(1).rho = ones(length(sspData(:, 1)), 1);
SSP.raw(1).alpha = zeros(length(sspData(:, 1)), 1);

% 2. 动态计算网格数 N 与相关参数
for medium = 1 : SSP.NMedia
    SSP.depth(medium) = SSP.raw(medium).z(end);
    SSP.sigma(medium) = 0; % 默认界面粗糙度
    
    Cm = min( SSP.raw(medium).Speed );
    if medium == 1
        D = SSP.depth( medium ) ;
    else
        D = SSP.depth( medium ) - SSP.depth( medium - 1 ) ;
    end
    SSP.N(medium) = floor( 16 * D * f0 / Cm );
end

%%
% 束控开角设置；只作用于从真实声源出发的路径
%   1) Beam.OpenAngle 只写入"从真实声源出发"的路径；
%   2) Beam.AzimuthRange 不写入 .env，后续在散射面元循环中用 atan2d(y,x) 判断；
%   3) 返回路径/接收端反向路径不使用发射束控。
BeamAlphaTx = normalizeBeamOpenAngleLocal(Beam);
NbeamsTx = calcNbeamsLocal(BeamAlphaTx,angleStepDeg);

%%
fileName = sprintf( 'Bottom_StoR.env' );
fileName = fullfile( TempWorkDir, fileName );

fid = fopen( fileName,'w' );
fprintf( fid, '''Bottom Profile''\t\n' );
fprintf( fid, '%8.2f  \t \t \t ! Frequency (Hz) \n', f0 );
fprintf( fid, '%5i    \t \t \t ! NMedia \n', SSP.NMedia );
fprintf( fid, '''%s'' \t \t \t \t ! Top Option \n', TopOpt );
% 介质层

for medium = 1 : SSP.NMedia
    fprintf( fid, '%5i %4.2f %6.2f \t ! N sigma depth \n', SSP.N( medium ), SSP.sigma( medium ), SSP.depth( medium ) );
    for ii = 1 : length( SSP.raw( medium ).z )
        fprintf( fid, '%4.2f   %6.2f %6.2f %6.2f   %6.6f %6.2f / \t ! z c cs rho α αs\n', ...
            SSP.raw( medium ).z( ii ), SSP.raw( medium ).Speed( ii ), 0,  ...
            SSP.raw( medium ).rho( ii ) , SSP.raw( medium ).alpha( ii ) , 0 );
    end
end

% 无限大半空间
fprintf( fid, '''%s'' %6.2f  \t \t ! Bottom Option, rms \n', BotOpt, rmsB);
if ( BotOpt== 'A' )
    fprintf( fid, '%.2f %6.2f %6.2f %6.2f %6.2f %6.2f /  \t ! lower halfspace \n', ...
        SSP.depth( end ), cB, cBs, rhoB, alphaB, alphaBs);
end

% 声源深度
fprintf( fid, '%5i \t \t \t \t ! NSz \n', 1 );
fprintf( fid, '    %6.2f  / \t \t ! SD(1:NSD) (m) \n', Sd );

% 接收器深度
fprintf( fid, '%5i \t \t \t \t ! NRz \n', 1 );
fprintf( fid, '    %6.2f  / \t \t ! RD(1:NRD) (m) \n', Rd );

% 接收距离
fprintf( fid, '%9i \t \t \t ! NRr \n', 2);
fprintf(fid,stoRSpec.RangeLineFormat,stoRSpec.RangesM(1)/1000,stoRSpec.RangesM(2)/1000);

% Run Type
RunType = 'A';
fprintf( fid, '''%s'' \t \t \t \t ! ''R/C/I/S'' \n', RunType );
Nbeams = NbeamsTx;
fprintf( fid, '%5i \t \t \t \t ! Nbeams \n', Nbeams );
BeamAlpha = BeamAlphaTx;
fprintf( fid, '%.2f %.2f / \t \t ! angles (degrees) \n', BeamAlpha( 1 ), BeamAlpha( end ) );
 BeamDeltas = 0; ZBox = zBox; RBox = stoRSpec.RBoxKm;
fprintf( fid, '%.2f %.2f %.2f \t ! deltas (m) Box.z (m) Box.r (km) \n', BeamDeltas, ZBox, RBox );

fclose( fid );


%%
fileName = sprintf( 'Bottom_BtoR.env');
fileName = fullfile( TempWorkDir, fileName );
fid = fopen( fileName,'w' );
fprintf( fid, '''Bottom Profile''\t\n' );
fprintf( fid, '%8.2f  \t \t \t ! Frequency (Hz) \n', f0 );
fprintf( fid, '%5i    \t \t \t ! NMedia \n', SSP.NMedia );
fprintf( fid, '''%s'' \t \t \t \t ! Top Option \n', TopOpt );
for medium = 1 : SSP.NMedia    %% 介质层
    fprintf( fid, '%5i %4.2f %6.2f \t ! N sigma depth \n', SSP.N( medium ), SSP.sigma( medium ), SSP.depth( medium ) );
    for ii = 1 : length( SSP.raw( medium ).z )
        fprintf( fid, '%4.2f   %6.2f %6.2f %6.2f   %6.6f %6.2f / \t ! z c cs rho α αs\n', ...
            SSP.raw( medium ).z( ii ), SSP.raw( medium ).Speed( ii ), 0,  ...
            SSP.raw( medium ).rho( ii ) , SSP.raw( medium ).alpha( ii ) , 0 );
    end
end
fprintf( fid, '''%s'' %6.2f  \t \t ! Bottom Option, rms \n', BotOpt, rmsB);    %% 无限大半空间
if ( BotOpt== 'A' )
    fprintf( fid, '%.2f %6.2f %6.2f %6.2f %6.2f %6.2f /  \t ! lower halfspace \n', ...
        SSP.depth( end ), cB, cBs, rhoB, alphaB, alphaBs);
end
fprintf( fid, '%5i \t \t \t \t ! NSz \n', 1 );    %% 声源深度
fprintf( fid, '    %6.2f  / \t \t ! SD(1:NSD) (m) \n', SSP.depth( end ) - 0.01);
fprintf( fid, '%5i \t \t \t \t ! NRz \n', 1 );           %% 接收器深度
fprintf( fid, '    %6.2f  / \t \t ! RD(1:NRD) (m) \n', Rd );
 fprintf( fid, '%9i \t \t \t ! NRr \n', btoRSpec.NRange );            % 接收距离
 fprintf(fid,btoRSpec.RangeLineFormat,btoRSpec.RangesM(1)/1000,btoRSpec.RangesM(2)/1000);
RunType = 'A';             % Run Type
fprintf( fid, '''%s'' \t \t \t \t ! ''R/C/I/S'' \n', RunType );
% Bottom_BtoR：海底散射点 -> 接收点的返回路径，不使用发射束控。
% 此处保留向上半空间搜索。
BeamAlpha = [0, -90];
 Nbeams = calcNbeamsLocal(BeamAlpha,angleStepDeg);
fprintf( fid, '%5i \t \t \t \t ! Nbeams \n', Nbeams );
fprintf( fid, '%.2f %.2f / \t \t ! angles (degrees) \n', BeamAlpha( 1 ), BeamAlpha( end ) );
 BeamDeltas = 0; ZBox = zBox; RBox = btoRSpec.RBoxKm;
fprintf( fid, '%.2f %.2f %.2f \t ! deltas (m) Box.z (m) Box.r (km) \n', BeamDeltas, ZBox, RBox );
fclose( fid );

%%
fileName = sprintf( 'Bottom_StoB.env' );
fileName = fullfile( TempWorkDir, fileName );
fid = fopen( fileName,'w' );
fprintf( fid, '''Bottom Profile''\t\n' );
fprintf( fid, '%8.2f  \t \t \t ! Frequency (Hz) \n', f0 );
fprintf( fid, '%5i    \t \t \t ! NMedia \n', SSP.NMedia );
fprintf( fid, '''%s'' \t \t \t \t ! Top Option \n', TopOpt );
for medium = 1 : SSP.NMedia    %% 介质层
    fprintf( fid, '%5i %4.2f %6.2f \t ! N sigma depth \n', SSP.N( medium ), SSP.sigma( medium ), SSP.depth( medium ) );
    for ii = 1 : length( SSP.raw( medium ).z )
        fprintf( fid, '%4.2f   %6.2f %6.2f %6.2f   %6.6f %6.2f / \t ! z c cs rho α αs\n', ...
            SSP.raw( medium ).z( ii ), SSP.raw( medium ).Speed( ii ), 0,  ...
            SSP.raw( medium ).rho( ii ) , SSP.raw( medium ).alpha( ii ) , 0 );
    end
end
fprintf( fid, '''%s'' %6.2f  \t \t ! Bottom Option, rms \n', BotOpt, rmsB);    %% 无限大半空间
if ( BotOpt== 'A' )
    fprintf( fid, '%.2f %6.2f %6.2f %6.2f %6.2f %6.2f /  \t ! lower halfspace \n', ...
        SSP.depth( end ), cB, cBs, rhoB, alphaB, alphaBs);
end
fprintf( fid, '%5i \t \t \t \t ! NSz \n', 1 );    %% 声源深度
fprintf( fid, '    %6.2f  / \t \t ! SD(1:NSD) (m) \n',  Sd);
fprintf( fid, '%5i \t \t \t \t ! NRz \n', 1 );           %% 接收器深度
fprintf( fid, '    %6.2f  / \t \t ! RD(1:NRD) (m) \n', SSP.depth( end ) - 0.01 );
 fprintf( fid, '%9i \t \t \t ! NRr \n', stoBSpec.NRange );            % 接收距离
 fprintf(fid,stoBSpec.RangeLineFormat,stoBSpec.RangesM(1)/1000,stoBSpec.RangesM(2)/1000);
RunType = 'A';             % Run Type
fprintf( fid, '''%s'' \t \t \t \t ! ''R/C/I/S'' \n', RunType );
% 从真实声源出发：使用发射束控俯仰角 Beam.OpenAngle
Nbeams = NbeamsTx;
fprintf( fid, '%5i \t \t \t \t ! Nbeams \n', Nbeams );
BeamAlpha = BeamAlphaTx;
fprintf( fid, '%.2f %.2f / \t \t ! angles (degrees) \n', BeamAlpha( 1 ), BeamAlpha( end ) );
 BeamDeltas = 0; ZBox = zBox ; RBox = stoBSpec.RBoxKm;
fprintf( fid, '%.2f %.2f %.2f \t ! deltas (m) Box.z (m) Box.r (km) \n', BeamDeltas, ZBox, RBox );
 fclose( fid );

EnvAudit=struct('PropagationProfile',PropagationSpec.Profile, ...
    'ExplicitPropagationSpec',true,'PaperEligible',PropagationSpec.PaperEligible, ...
    'SourceToBottom',stoBSpec,'BottomToReceiver',btoRSpec, ...
    'SourceToReceiver',stoRSpec,'LaunchAngleStepDeg',angleStepDeg, ...
    'TxNBeams',NbeamsTx,'ReturnNBeams',calcNbeamsLocal([0 -90],angleStepDeg));

end

function S=validateWriterSpecLocal(S,pathName)
required={'EnvRangeMaxM','NRange','RBoxKm','RangesM','RangeLineFormat'};
for k=1:numel(required)
    if ~isfield(S,required{k}) || isempty(S.(required{k}))
        error('G3:IncompleteWriterSpec','%s spec missing %s.',pathName,required{k});
    end
end
if numel(S.RangesM)~=2 || S.RangesM(1)~=0 || S.RangesM(2)~=S.EnvRangeMaxM
    error('G3:InvalidWriterRanges','%s RangesM must equal [0 EnvRangeMaxM].',pathName);
end
end

function BeamAlpha = normalizeBeamOpenAngleLocal(Beam)
% normalizeBeamOpenAngleLocal
% 读取 Beam.OpenAngle 并整理为 [upper lower]。
% 若 Beam 缺失或字段无效，则默认全俯仰角 [90 -90]。
    defaultAlpha = [90, -90];

    if nargin < 1 || isempty(Beam) || ~isstruct(Beam) || ...
            ~isfield(Beam, 'OpenAngle') || isempty(Beam.OpenAngle)
        BeamAlpha = defaultAlpha;
        return;
    end

    BeamAlpha = double(Beam.OpenAngle(:).');
    BeamAlpha = BeamAlpha(isfinite(BeamAlpha));

    if numel(BeamAlpha) < 2
        BeamAlpha = defaultAlpha;
        return;
    end

    BeamAlpha = BeamAlpha(1:2);

    % BELLHOP angle line沿用项目原约定：[upper lower]
    BeamAlpha = [max(BeamAlpha), min(BeamAlpha)];

    % 限制到常用俯仰角范围
    BeamAlpha = max(min(BeamAlpha, 90), -90);

    if BeamAlpha(1) == BeamAlpha(2)
        % 极窄波束时给一个很小角宽，避免 Nbeams=1 导致射线追踪不稳定
        BeamAlpha = [min(90, BeamAlpha(1)+0.005), max(-90, BeamAlpha(2)-0.005)];
    end
end

function Nbeams = calcNbeamsLocal(BeamAlpha,angleStepDeg)
% calcNbeamsLocal
% 根据角度范围计算射线数，保持原 0.01° 角分辨率。
    if nargin<2 || isempty(angleStepDeg), angleStepDeg = 0.01; end
    Nbeams = round(abs(BeamAlpha(1) - BeamAlpha(2)) / angleStepDeg) + 1;
    Nbeams = max(2, Nbeams);
end


