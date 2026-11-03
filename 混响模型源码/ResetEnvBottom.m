function [ ] = ResetEnvBottom( f0, Sd, Rd, RecvRange, Sediment, TempWorkDir, sspData, Beam, Rmax, waterDepth)

if nargin < 9 || isempty(Rmax), Rmax = max(RecvRange, 60000); end
if nargin < 10 || isempty(waterDepth), waterDepth = max(sspData(:,1)); end
rangeMaxM = max([double(Rmax), double(RecvRange), 1000]);
rangeBoxKm = ceil(rangeMaxM/1000) + 1;
nRange = ceil(rangeMaxM) + 1;
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
% 发射角域：interface source leg 使用 Main.Support + Secondary.Supports
% 的连续包络；residual 不扩大包络。StoR 为直达/多途候选搜索，固定全角。
[Beam.OpenAngle,~] = ResolveBeamOpenAngle(Beam);
BeamAlphaInterface = normalizeBeamOpenAngleLocal(Beam);
NbeamsInterface = calcNbeamsLocal(BeamAlphaInterface);
BeamAlphaStoR = [90,-90];
NbeamsStoR = calcNbeamsLocal(BeamAlphaStoR);

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
fprintf( fid, '%4.3f %6.3f  /  \t ! R(1:NR ) (km) \n', 0, RecvRange/1000);

% Run Type
RunType = 'A';
fprintf( fid, '''%s'' \t \t \t \t ! ''R/C/I/S'' \n', RunType );
% Bottom_StoR searches all direct/multipath source candidates.
Nbeams = NbeamsStoR;
fprintf( fid, '%5i \t \t \t \t ! Nbeams \n', Nbeams );
BeamAlpha = BeamAlphaStoR;
fprintf( fid, '%.2f %.2f / \t \t ! angles (degrees) \n', BeamAlpha( 1 ), BeamAlpha( end ) );
BeamDeltas = 0; ZBox = zBox; RBox = rangeBoxKm;
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
fprintf( fid, '%9i \t \t \t ! NRr \n', nRange );            % 接收距离
fprintf( fid, '%4.2f %6.2f    /  \t ! R(1:NR ) (km) \n', 0, rangeMaxM/1000 );
RunType = 'A';             % Run Type
fprintf( fid, '''%s'' \t \t \t \t ! ''R/C/I/S'' \n', RunType );
% Bottom_BtoR：海底散射点 -> 接收点的返回路径，不使用发射束控。
% 此处保留向上半空间搜索。
BeamAlpha = [0, -90];
Nbeams = calcNbeamsLocal(BeamAlpha);
fprintf( fid, '%5i \t \t \t \t ! Nbeams \n', Nbeams );
fprintf( fid, '%.2f %.2f / \t \t ! angles (degrees) \n', BeamAlpha( 1 ), BeamAlpha( end ) );
BeamDeltas = 0; ZBox = zBox; RBox = rangeBoxKm;
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
fprintf( fid, '%9i \t \t \t ! NRr \n', nRange );            % 接收距离
fprintf( fid, '%4.2f %6.2f    /  \t ! R(1:NR ) (km) \n', 0, rangeMaxM/1000 );
RunType = 'A';             % Run Type
fprintf( fid, '''%s'' \t \t \t \t ! ''R/C/I/S'' \n', RunType );
% 从真实声源到界面：使用已解析的 Main+Secondary 连续包络。
Nbeams = NbeamsInterface;
fprintf( fid, '%5i \t \t \t \t ! Nbeams \n', Nbeams );
BeamAlpha = BeamAlphaInterface;
fprintf( fid, '%.2f %.2f / \t \t ! angles (degrees) \n', BeamAlpha( 1 ), BeamAlpha( end ) );
BeamDeltas = 0; ZBox = zBox ; RBox = rangeBoxKm;
fprintf( fid, '%.2f %.2f %.2f \t ! deltas (m) Box.z (m) Box.r (km) \n', BeamDeltas, ZBox, RBox );
fclose( fid );

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

function Nbeams = calcNbeamsLocal(BeamAlpha)
% calcNbeamsLocal
% 根据角度范围计算射线数，保持原 0.01° 角分辨率。
    angleStepDeg = 0.01;
    Nbeams = round(abs(BeamAlpha(1) - BeamAlpha(2)) / angleStepDeg) + 1;
    Nbeams = max(2, Nbeams);
end


