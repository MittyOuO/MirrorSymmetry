function [InputParams, resolved, cfg] = BuildInputParamsFromJson(cfg, jsonFile)
%BuildInputParamsFromJson Validate one JSON case and map it to the core model.
if ~isstruct(cfg), error('BuildInputParamsFromJson:InvalidConfig', 'Decoded JSON must be a struct.'); end
jsonDir = fileparts(char(jsonFile));
warnings = {};

requiredSections = {'File','Simulation','Signal','Beam','Geometry','Array','Environment', ...
    'Bottom','Scattering','SeaSurface','PlatformMotion','Computation','Output','BTR','Runtime'};
for k = 1:numel(requiredSections)
    if ~isfield(cfg,requiredSections{k}) || ~isstruct(cfg.(requiredSections{k}))
        error('BuildInputParamsFromJson:MissingSection', 'Missing JSON object: %s.', requiredSections{k});
    end
end

% RandomSeed and ScatterGrid were experimental external controls.  The
% production model now uses one fixed grid and one shared phase rule for all
% frequency channels, so remove legacy fields instead of exposing them.
if isfield(cfg.Computation,'RandomSeed')
    cfg.Computation = rmfield(cfg.Computation,'RandomSeed');
    warnings{end+1} = 'Deprecated Computation.RandomSeed was ignored and removed.';
end
if isfield(cfg.Computation,'ScatterGrid')
    cfg.Computation = rmfield(cfg.Computation,'ScatterGrid');
    warnings{end+1} = 'Deprecated Computation.ScatterGrid was ignored and removed.';
end
if isfield(cfg.Computation,'Itg')
    cfg.Computation = rmfield(cfg.Computation,'Itg');
    warnings{end+1} = 'Computation.Itg is internal (fixed at 0.02 s); external value was ignored and removed.';
end
if isfield(cfg.Computation,'frequencyChannelMode')
    cfg.Computation = rmfield(cfg.Computation,'frequencyChannelMode');
    warnings{end+1} = ['Deprecated Computation.frequencyChannelMode was ignored and removed; ' ...
        'propagation frequencies are selected automatically from Signal.'];
end

fs = requiredPositiveLocal(cfg.Simulation,'fsSim','Simulation');
tx = buildSignalLocal(cfg.Signal, fs, jsonDir);

fBeam = requiredPositiveLocal(cfg.Beam,'fBeam','Beam');
arrayType = double(requiredScalarLocal(cfg.Beam,'ArrayType','Beam'));
if ~ismember(arrayType,1:4) || fix(arrayType) ~= arrayType
    error('BuildInputParamsFromJson:InvalidArrayType', 'Beam.ArrayType must be 1/2/3/4.');
end
[beam, elemPos, beamResolved, beamWarnings] = resolveBeamLocal(cfg.Beam, arrayType, fBeam);
warnings = [warnings, beamWarnings]; %#ok<AGROW>

waterDepth = requiredPositiveLocal(cfg.Environment,'waterDepth','Environment');
sspPath = resolvePathLocal(requiredTextLocal(cfg.Environment,'sspPath','Environment'), jsonDir);
sspRaw = LoadSSPFile(sspPath);
[sspFinal, sspAxisInfo] = AdjustSSPToWaterDepth(sspRaw, waterDepth);

[sediment, bottomResolved] = resolveBottomLocal(cfg.Bottom);
scatteringResolved = ResolveScatteringPreset(cfg.Scattering);

saveSelection = unique(double(cfg.Output.saveSelection(:).'));
if isempty(saveSelection), saveSelection=0; end
if any(~ismember(saveSelection,0:5))
    error('BuildInputParamsFromJson:InvalidOutputSelection', 'Output.saveSelection values must be 0..5.');
end
if numel(saveSelection)>1, saveSelection(saveSelection==0)=[]; end
cfg.Output.saveSelection=saveSelection;
btrRequested = logical(fieldOrLocal(cfg.BTR,'enable',false));
btrForced = any(ismember(saveSelection,[4 5])) && ~btrRequested;
needBTR = btrRequested || any(ismember(saveSelection,[4 5]));
if btrForced, warnings{end+1} = 'BTR enabled because Output.saveSelection contains 4 or 5.'; end

InputParams = struct();
InputParams.Rd = requiredNonnegativeLocal(cfg.Geometry,'receiverDepth','Geometry');
InputParams.Sd = requiredNonnegativeLocal(cfg.Geometry,'sourceDepth','Geometry');
if isfield(beamResolved,'Sd') && isfinite(beamResolved.Sd), InputParams.Sd = beamResolved.Sd; end
InputParams.RecvRange = requiredNonnegativeLocal(cfg.Geometry,'transceiverRange','Geometry');
InputParams.NArray = round(requiredPositiveLocal(cfg.Array,'elementCount','Array'));
InputParams.ArraySpacing = requiredPositiveLocal(cfg.Array,'spacing','Array');
rxPitchUser = double(fieldOrLocal(cfg.Array,'receiverPitchDeg',0));
rxHeadingDeg = double(fieldOrLocal(cfg.Array,'headingDeg',0));
if ~isscalar(rxPitchUser) || ~isfinite(rxPitchUser) || abs(rxPitchUser) >= 90
    error('BuildInputParamsFromJson:InvalidReceiverPitch', ...
        'Array.receiverPitchDeg must be a finite scalar with abs(value) < 90 deg.');
end
if ~isscalar(rxHeadingDeg) || ~isfinite(rxHeadingDeg)
    error('BuildInputParamsFromJson:InvalidReceiverHeading', ...
        'Array.headingDeg must be a finite scalar in degrees.');
end
% 用户正值表示远离声源端向上；底层 z 为正深度且 PitchDeg>0
% 表示远端向下，所以传入三维接收阵模型时必须取反。
InputParams.RxArrayPitchDeg_User = rxPitchUser;
InputParams.TowedArray = struct( ...
    'GeometryMode','rigid_tilt', ...
    'PitchDeg',-rxPitchUser, ...
    'PitchSource','json_user_pitch_negated_for_positive_depth', ...
    'ArrayHeadingDeg',rxHeadingDeg, ...
    'CenterX',InputParams.RecvRange, ...
    'CenterY',0, ...
    'CenterDepth',InputParams.Rd, ...
    'N',InputParams.NArray, ...
    'd',InputParams.ArraySpacing, ...
    'ReferenceElement',(InputParams.NArray+1)/2);
InputParams.WaterDepth = waterDepth;
InputParams.SSP = sspFinal;
InputParams.SSPAxisInfo = sspAxisInfo;
InputParams.Sediment = sediment;
% 核心ScatterFunc的坡度单位是rad；在JSON解析边界只转换一次。
InputParams.Tht = scatteringResolved.bottomRmsSlopeRad;
InputParams.Miu = scatteringResolved.miuDb;
InputParams.v = scatteringResolved.roughnessDb;
InputParams.fs = fs;
InputParams.fsSig = fs;
InputParams.Itg = 0.02;
InputParams.Rmax = requiredPositiveLocal(cfg.Computation,'Rmax','Computation');
InputParams.TWindow = requiredPositiveLocal(cfg.Computation,'TWindow','Computation');
InputParams.TWindowCompute = double(fieldOrLocal(cfg.Computation,'TWindowCompute',InputParams.TWindow));
InputParams.TWindowDisplay = double(fieldOrLocal(cfg.Computation,'TWindowDisplay',InputParams.TWindow));
InputParams.RunMode = double(fieldOrLocal(cfg.Computation,'RunMode',2));
InputParams.SkipFastRL = logical(fieldOrLocal(cfg.Computation,'SkipFastRL',true));
InputParams.SkipSynthesis = false;
InputParams.NeedBTR = needBTR;
% Event tables are an internal BTR intermediate only.  They are never an
% independently selectable diagnostic product.
InputParams.SaveEvents = needBTR;
InputParams.TxSigInput = tx;
InputParams.f0 = sharedFrequencyForCompatibilityLocal(tx);
% Keep the resolved display/nominal Beam immutable and create one fresh
% computation copy.  All downstream paths (FastRL, direct/time-domain,
% bottom/surface events and BTR event gains) consume InputParams.Beam.
beam.fBeam = fBeam;
InputParams.BeamDisplay = beam;
InputParams.Beam = InputParams.BeamDisplay;
InputParams.BeamComputeAudit = struct( ...
    'Applied',false,'BoostDB',0,'NumChangedEntries',0, ...
    'Changes',struct([]),'Policy','BeamCompute_equals_BeamDisplay');
InputParams.ArrayElementPositions = elemPos;
inputWindSpeed = double(fieldOrLocal(cfg.SeaSurface,'windSpeed',0));
InputParams.SeaState = double(fieldOrLocal(cfg.SeaSurface,'seaState',0));
if ~isscalar(inputWindSpeed) || ~isfinite(inputWindSpeed) || inputWindSpeed < 0
    error('BuildInputParamsFromJson:InvalidWindSpeed', ...
        'SeaSurface.windSpeed必须为有限非负标量，单位m/s。');
end
surfaceWind=ResolveSeaSurfaceWind(InputParams.SeaState,inputWindSpeed);
InputParams.U=surfaceWind.EffectiveWindSpeedMps;
if ~isscalar(InputParams.SeaState) || ~isfinite(InputParams.SeaState) || ...
        InputParams.SeaState < 0 || InputParams.SeaState > 12 || ...
        fix(InputParams.SeaState) ~= InputParams.SeaState
    error('BuildInputParamsFromJson:InvalidSeaState', ...
        'SeaSurface.seaState必须为0到12之间的整数。');
end
InputParams.EnableSurfaceDynamic = logical(fieldOrLocal(cfg.SeaSurface,'frequencySpread',false));
InputParams.SurfaceDynamic = struct( ...
    'Enable',InputParams.EnableSurfaceDynamic, ...
    'Strength',double(fieldOrLocal(cfg.SeaSurface,'spreadStrength',1)), ...
    'BaseSigmaPerWind',double(fieldOrLocal(cfg.SeaSurface,'baseSigmaPerWind',0.004)), ...
    'PowerLaw',double(fieldOrLocal(cfg.SeaSurface,'powerLaw',1.15)), ...
    'MaxSigmaTime',double(fieldOrLocal(cfg.SeaSurface,'maxSigmaTime',0.08)), ...
    'PreserveEnergy',logical(fieldOrLocal(cfg.SeaSurface,'preserveEnergy',true)));
InputParams.DopplerEnable = logical(fieldOrLocal(cfg.PlatformMotion,'enable',false));
InputParams.PlatformSpeedKn = double(fieldOrLocal(cfg.PlatformMotion,'speedKn',0));
InputParams.DopplerMode = char(fieldOrLocal(cfg.PlatformMotion,'dopplerMode','two_way'));
InputParams.DopplerCosine = double(fieldOrLocal(cfg.PlatformMotion,'dopplerCosine',1));
InputParams.SpreadTime = double(fieldOrLocal(cfg.PlatformMotion,'timeSpreadMs',0));
InputParams.SourceLevel = double(fieldOrLocal(fieldOrLocal(cfg,'Intensity',struct()),'sourceLevel',231));
InputParams.Sensitivity = double(fieldOrLocal(fieldOrLocal(cfg,'Intensity',struct()),'sensitivity',-170));
InputParams.AmpGain = double(fieldOrLocal(fieldOrLocal(cfg,'Intensity',struct()),'ampGain',20));
InputParams.NL = double(fieldOrLocal(fieldOrLocal(cfg,'Intensity',struct()),'environmentNoise',50));
InputParams.TxSigInput.SourceLevel = InputParams.SourceLevel;
InputParams.WaterColumnVolume = buildWaterColumnVolumeLocal(cfg, InputParams);
InputParams.OutputSelection = saveSelection;
InputParams.OutputPath = resolvePathLocal(requiredTextLocal(cfg.File,'outputPath','File'),jsonDir);
InputParams.TempWorkDir = resolvePathLocal(requiredTextLocal(cfg.Runtime,'TempWorkDir','Runtime'),jsonDir);
InputParams.KeepTempFiles = logical(fieldOrLocal(cfg.Runtime,'KeepTempFiles',false));
% Internal readZSDX IPC switch.  It is written only into the per-run JSON
% generated by readZSDX and is not a physical-model input.
InputParams.ReturnToCaller = logical(fieldOrLocal(cfg.Runtime,'ReturnToCaller',false));
InputParams.BTRParams = buildBTRLocal(cfg.BTR, cfg, fBeam, fs, sspFinal, InputParams);
InputParams.BTRForcedByOutputSelection = btrForced;
InputParams.OptionBorder = ternaryLocal(double(fieldOrLocal(cfg.Environment,'modelType',1)) == 1, 1, 0);
% 海面混响启用时同时加入两种不同的体积项：NRL近海面气泡云，以及
% 独立的水体体积混响。两者在诊断信息中分别记录，不允许混为一项。
InputParams.EnableSurfaceBubbleVolume = InputParams.OptionBorder == 0;
InputParams.EnableWaterColumnVolume = InputParams.OptionBorder == 0;
InputParams.WaterColumnVolume.Enable = InputParams.EnableWaterColumnVolume;
InputParams.InputJson = char(jsonFile);

cfg.Beam.fBeam = fBeam;
if arrayType == 1, cfg.Beam.verticalArray.fBeam = fBeam;
elseif arrayType == 2, cfg.Beam.horiArray.fBeam = fBeam;
elseif arrayType == 3, cfg.Beam.cylinArray.fBeam = fBeam; end
resolved = struct();
resolved.warnings = warnings;
resolved.beamResolved = beamResolved;
resolved.beamComputationBoost = InputParams.BeamComputeAudit;
resolved.bottomResolved = bottomResolved;
resolved.scatteringResolved = scatteringResolved;
resolved.surfaceResolved = struct( ...
    'seaState',InputParams.SeaState, ...
    'inputWindSpeedMps',surfaceWind.InputWindSpeedMps, ...
    'effectiveWindSpeedMps',surfaceWind.EffectiveWindSpeedMps, ...
    'standardWindRangeMps',surfaceWind.StandardWindRangeMps, ...
    'representativeWindSpeedMps',surfaceWind.RepresentativeWindSpeedMps, ...
    'windResolutionSource',surfaceWind.ResolutionSource, ...
    'surfaceEnabled',InputParams.OptionBorder==0, ...
    'bubbleVolumeEnabled',InputParams.EnableSurfaceBubbleVolume, ...
    'waterColumnVolumeEnabled',InputParams.EnableWaterColumnVolume, ...
    'bubbleOnsetWindSpeedMps',3, ...
    'scatteringMode','NRL interface + bubble cloud + independent water-column volume reverberation');
resolved.sspResolved = struct('sourcePath',sspPath,'waterDepth',waterDepth, ...
    'pointCount',size(sspFinal,1),'firstDepth',sspFinal(1,1),'lastDepth',sspFinal(end,1), ...
    'firstSoundSpeed',sspFinal(1,2),'lastSoundSpeed',sspFinal(end,2), ...
    'axisInfo',sspAxisInfo);
resolved.btrForcedByOutputSelection = btrForced;
resolved.outputPath = InputParams.OutputPath;
resolved.tempWorkDir = InputParams.TempWorkDir;
end

function volume = buildWaterColumnVolumeLocal(cfg, InputParams)
% 内部验收模型：参数不在交付人员的一次性配置区开放。
V = fieldOrLocal(cfg,'WaterColumnVolume',struct());
volume = struct( ...
    'Enable',false, ...
    'NearReferenceTransferLevelDb',double(fieldOrLocal(V,'nearReferenceTransferLevelDb',-137.0)), ...
    'NearReferenceDelaySec',double(fieldOrLocal(V,'nearReferenceDelaySec',1.5)), ...
    'NearDecayRateDbPerSec',double(fieldOrLocal(V,'nearDecayRateDbPerSec',5.5)), ...
    'NearOnsetDelaySec',double(fieldOrLocal(V,'nearOnsetDelaySec',0.55)), ...
    'NearFullDelaySec',double(fieldOrLocal(V,'nearFullDelaySec',1.0)), ...
    'NearFadeDelaySec',double(fieldOrLocal(V,'nearFadeDelaySec',3.8)), ...
    'NearOffDelaySec',double(fieldOrLocal(V,'nearOffDelaySec',4.55)), ...
    'ReferenceTransferLevelDb',double(fieldOrLocal(V,'referenceTransferLevelDb',-130.5)), ...
    'ReferenceDelaySec',double(fieldOrLocal(V,'referenceDelaySec',5.75)), ...
    'PowerLawExponent',double(fieldOrLocal(V,'powerLawExponent',2.6)), ...
    'OnsetDelaySec',double(fieldOrLocal(V,'onsetDelaySec',4.45)), ...
    'FullDelaySec',double(fieldOrLocal(V,'fullDelaySec',5.15)), ...
    'BandLowHz',double(fieldOrLocal(V,'bandLowHz',475)), ...
    'BandHighHz',double(fieldOrLocal(V,'bandHighHz',525)), ...
    'RandomSeed',round(double(fieldOrLocal(V,'randomSeed',20260811))));
values=[volume.NearReferenceTransferLevelDb volume.NearReferenceDelaySec ...
    volume.NearDecayRateDbPerSec volume.NearOnsetDelaySec volume.NearFullDelaySec ...
    volume.NearFadeDelaySec volume.NearOffDelaySec ...
    volume.ReferenceTransferLevelDb volume.ReferenceDelaySec ...
    volume.PowerLawExponent volume.OnsetDelaySec volume.FullDelaySec ...
    volume.BandLowHz volume.BandHighHz volume.RandomSeed];
validateattributes(values,{'numeric'},{'real','finite'});
if volume.NearReferenceDelaySec<=0 || volume.NearDecayRateDbPerSec<=0 || ...
        volume.NearOnsetDelaySec<0 || volume.NearFullDelaySec<=volume.NearOnsetDelaySec || ...
        volume.NearFadeDelaySec<=volume.NearFullDelaySec || ...
        volume.NearOffDelaySec<=volume.NearFadeDelaySec || ...
        volume.ReferenceDelaySec<=0 || volume.PowerLawExponent<=0 || ...
        volume.OnsetDelaySec<0 || volume.FullDelaySec<=volume.OnsetDelaySec || ...
        volume.BandLowHz<=0 || volume.BandHighHz<=volume.BandLowHz || ...
        volume.BandHighHz>=InputParams.fs/2
    error('BuildInputParamsFromJson:InvalidWaterColumnVolume', ...
        'WaterColumnVolume internal parameters are invalid for fsSim.');
end
end

function tx = buildSignalLocal(S, fs, baseDir)
type = upper(strrep(strrep(char(requiredTextLocal(S,'type','Signal')),'+','_'),'-','_'));
allowed = {'CW','HFM','LFM','HFM_CW','CW_HFM','CUSTOM'};
if ~ismember(type,allowed), error('BuildInputParamsFromJson:InvalidSignalType','Unsupported Signal.type: %s',type); end
tx = struct('sigType',type,'fsSig',fs,'normalizeMode','peak');
if contains(type,'CW')
    tx.fCW = requiredPositiveLocal(S,'frequency','Signal');
    tx.TpCW = requiredPositiveLocal(S,'cwPulseWidth','Signal');
end
if contains(type,'HFM') || strcmp(type,'LFM')
    tx.fStart = requiredPositiveLocal(S,'startFrequency','Signal');
    tx.fEnd = requiredPositiveLocal(S,'endFrequency','Signal');
    tx.HFMType = char(fieldOrLocal(S,'sweepType','up'));
    if strcmp(type,'LFM'), tx.TpLFM = requiredPositiveLocal(S,'hfmPulseWidth','Signal');
    else, tx.TpHFM = requiredPositiveLocal(S,'hfmPulseWidth','Signal'); end
end
if strcmp(type,'CUSTOM')
    tx.sigType = 'custom';
    tx.customPath = resolvePathLocal(requiredTextLocal(S,'customPath','Signal'),baseDir);
end
end

function [Beam, elemPos, info, warnings] = resolveBeamLocal(B, arrayType, fBeam)
warnings = {};
beamCfg = struct('centerDepth',double(fieldOrLocal(B,'centerDepth',0)), ...
    'azimuthSearchRangeDeg',double(fieldOrLocal(B,'azimuthSearchRangeDeg',[-180 180])));
switch arrayType
    case 1
        beamCfg.arrayType = 'vertical'; beamCfg.verticalArray = B.verticalArray;
        warnings = compareLegacyFBeamLocal(beamCfg.verticalArray,fBeam,'Beam.verticalArray.fBeam');
        beamCfg.verticalArray.fBeam = fBeam;
    case 2
        beamCfg.arrayType = 'linear'; beamCfg.horiArray = B.horiArray;
        warnings = compareLegacyFBeamLocal(beamCfg.horiArray,fBeam,'Beam.horiArray.fBeam');
        beamCfg.horiArray.fBeam = fBeam;
    case 3
        beamCfg.arrayType = 'cylindrical'; A = B.cylinArray;
        warnings = compareLegacyFBeamLocal(A,fBeam,'Beam.cylinArray.fBeam');
        A.M = requiredPositiveLocal(A,'ringElementCount','Beam.cylinArray');
        A.m = requiredPositiveLocal(A,'verticalLayerCount','Beam.cylinArray');
        A.fBeam = fBeam; beamCfg.cylinArray = A;
    case 4
        beamCfg.arrayType = 'custom';
end
if arrayType == 4
    if isfield(B,'customMainBeam') && isstruct(B.customMainBeam)
        lower = requiredScalarLocal(B.customMainBeam,'lowerDeg','Beam.customMainBeam');
        upper = requiredScalarLocal(B.customMainBeam,'upperDeg','Beam.customMainBeam');
    elseif isfield(B,'BeamElevLower') && isfield(B,'BeamElevUpper')
        lower = double(B.BeamElevLower); upper = double(B.BeamElevUpper);
        warnings{end+1} = 'Legacy BeamElevLower/BeamElevUpper mapped to Beam.customMainBeam.';
    else
        error('BuildInputParamsFromJson:MissingCustomMainBeam', ...
            'ArrayType=4 requires Beam.customMainBeam.lowerDeg/upperDeg.');
    end
    if lower > upper, error('BuildInputParamsFromJson:InvalidCustomMainBeam','customMainBeam.lowerDeg must be <= upperDeg.'); end
    mainBeam = [upper lower]; elemPos = zeros(0,3);
    info = struct('ArrayType','custom','MainBeam',mainBeam,'Sd',beamCfg.centerDepth,'fBeam',fBeam);
else
    [eq,elemPos] = ConfigureArrayBeam(beamCfg,'Plot',false);
    mainBeam = eq.OpenAngleRangeDeg;
    info = eq;
    heavyFields={'Pattern2D','Pattern3D','Projection3D','ElementPosition'};
    for kk=1:numel(heavyFields)
        if isfield(info,heavyFields{kk}), info=rmfield(info,heavyFields{kk}); end
    end
end
mainBeam = double(mainBeam(:).');
if isfield(B,'sideRangeDeg') && ~isempty(B.sideRangeDeg)
    sideRange = double(B.sideRangeDeg);
else
    sideRange = [mainBeam(2) mainBeam(2); mainBeam(1) mainBeam(1)];
end
% 精确兼容旧版“禁用旁瓣”哨兵；其他非法矩阵仍由严格校验报错。
if isequal(sideRange,[90 90;-90 -90])
    sideRange = [mainBeam(2) mainBeam(2);mainBeam(1) mainBeam(1)];
end
% 模型俯仰角顺序：sideRangeDeg=[下外 下内; 上内 上外]；
% sideDownDb=[下旁瓣 上旁瓣]。保留单标量兼容，自动复制到上下两侧。
sideDown = normalizeSideDownLocal(fieldOrLocal(B,'sideDownDb',[0 0]), ...
    'Beam.sideDownDb','[lower upper]');
ValidateBeamRanges(mainBeam,sideRange);

% azimuthSearchRangeDeg 只限制 ConfigureArrayBeam 的三维诊断扫描域。
% 非自定义阵型的模型主瓣必须使用主切面插值得到的方位 HPBW，
% 不能再被 JSON 搜索范围覆盖。
if arrayType ~= 4 && isfield(info,'AzimuthRangeDeg') && ~isempty(info.AzimuthRangeDeg)
    azRange = double(info.AzimuthRangeDeg);
else
    azRange = double(fieldOrLocal(B,'azimuthSearchRangeDeg',[-180 180]));
end
azRange = azRange(:).';
if numel(azRange) ~= 2 || any(~isfinite(azRange))
    error('BuildInputParamsFromJson:InvalidAzimuthRange', ...
        'Beam.azimuthSearchRangeDeg must contain two finite values.');
end
if isfield(B,'AzSideRangeDeg') && ~isempty(B.AzSideRangeDeg)
    azSideRange = double(B.AzSideRangeDeg);
else
    % 空数组明确表示左右旁瓣宽度均为 0。
    azSideRange = [azRange(1) azRange(1); azRange(2) azRange(2)];
end
validateAzimuthSideRangeLocal(azRange,azSideRange);
azSideDown = normalizeSideDownLocal(fieldOrLocal(B,'AzSideDownDb',[0 0]), ...
    'Beam.AzSideDownDb','[left right]');

Beam = struct('MainBeam',mainBeam,'SideRange',sideRange, ...
    'SideDown_dB',sideDown,'ElevSideDown_dB',sideDown, ...
    'OpenAngle',mainBeam, ...
    'AzimuthRange',azRange,'AzimuthSideRange',azSideRange, ...
    'AzimuthSideDown_dB',azSideDown, ...
    'fBeam',fBeam,'ArrayType',arrayType);
if arrayType ~= 4 && isfield(info,'WeightModelVersion') && info.WeightModelVersion >= 2
    Beam.WeightModelVersion = 2;
    Beam.ElevationWeightModel = info.ElevationWeightModel;
    Beam.AzimuthWeightModel = info.AzimuthWeightModel;
    % Existing JSON fields remain a backward-compatible manual override,
    % but apply to residual side regions only in V2.
    Beam.ResidualOverrideEnabled = ...
        (isfield(B,'sideRangeDeg') && ~isempty(B.sideRangeDeg)) || ...
        (isfield(B,'AzSideRangeDeg') && ~isempty(B.AzSideRangeDeg));
else
    Beam.WeightModelVersion = 1;
end
[Beam.OpenAngle,Beam.OpenAngleAudit] = ResolveBeamOpenAngle(Beam);
info.MainBeam = mainBeam; info.SideRange = sideRange;
info.SideDown_dB = sideDown; info.ElevSideDown_dB = sideDown;
info.AzimuthRange = azRange; info.AzimuthSideRange = azSideRange;
info.AzimuthSideDown_dB = azSideDown;
info.OpenAngle = Beam.OpenAngle; info.fBeam = fBeam;
end

function value = normalizeSideDownLocal(value,pathName,orderText)
value = double(value(:).');
if isscalar(value), value = [value value]; end
if numel(value) ~= 2 || any(~isfinite(value)) || any(value > 0)
    error('BuildInputParamsFromJson:InvalidSideDown', ...
        '%s must be a finite scalar <= 0 or a two-element %s vector.', ...
        pathName,orderText);
end
end

function validateAzimuthSideRangeLocal(mainRange,sideRange)
if ~isequal(size(sideRange),[2 2]) || any(~isfinite(sideRange(:)))
    error('BuildInputParamsFromJson:InvalidAzimuthSideRange', ...
        'Beam.AzSideRangeDeg must be empty or a finite 2-by-2 matrix.');
end
if any(sideRange(:) < -180-1e-9) || any(sideRange(:) > 180+1e-9)
    error('BuildInputParamsFromJson:InvalidAzimuthSideRange', ...
        'Beam.AzSideRangeDeg values must remain within [-180,180] deg.');
end

% 对非跨界主瓣执行严格的左外->左内->主瓣->右内->右外顺序检查。
mainRange = double(mainRange(:).');
isFull = abs(mainRange(2)-mainRange(1)) >= 359.999;
isWrapped = mainRange(1) > mainRange(2);
if ~isFull && ~isWrapped
    checks = [sideRange(1,1) <= sideRange(1,2), ...
        sideRange(1,2) <= mainRange(1), ...
        mainRange(2) <= sideRange(2,1), ...
        sideRange(2,1) <= sideRange(2,2)];
    if ~all(checks)
        error('BuildInputParamsFromJson:InvalidAzimuthSideOrdering', ...
            ['Beam.AzSideRangeDeg must satisfy leftOuter <= leftInner <= ', ...
             'mainLeft and mainRight <= rightInner <= rightOuter.']);
    end
end
end

function warnings = compareLegacyFBeamLocal(S,fBeam,pathName)
warnings = {};
if isfield(S,'fBeam') && ~isempty(S.fBeam) && double(S.fBeam) ~= fBeam
    warnings{1} = sprintf('%s=%g overridden by Beam.fBeam=%g.',pathName,double(S.fBeam),fBeam);
end
end

function [Sediment, resolved] = resolveBottomLocal(B)
mode = lower(string(fieldOrLocal(B,'mode','manual')));
if mode == "custom", mode = "manual"; end
switch mode
    case "manual"
        values = struct('type','manual','Cb',requiredPositiveLocal(B,'Cb','Bottom'), ...
            'Alphab',requiredNonnegativeLocal(B,'Alphab','Bottom'), ...
            'Rhob',requiredPositiveLocal(B,'Rhob','Bottom'));
    case "preset"
        values = GetBottomPreset(requiredTextLocal(B,'type','Bottom'));
    otherwise
        error('BuildInputParamsFromJson:InvalidBottomMode','Bottom.mode must be manual, preset, or custom.');
end
rmsSlope = requiredNonnegativeLocal(B,'rmsSlope','Bottom');
Sediment = struct('TopOpt','CVW','BotOpt','A','rmsB',rmsSlope, ...
    'cB',values.Cb,'cBs',0,'rhoB',values.Rhob,'alphaB',values.Alphab,'alphaBs',0);
resolved = struct('mode',char(mode),'type',values.type,'Cb',values.Cb, ...
    'Alphab',values.Alphab,'Rhob',values.Rhob,'rmsSlope',rmsSlope);
end

function P = buildBTRLocal(BTR,cfg,fBeam,fs,SSP,InputParams)
P = ResolveBTRParameters(BTR,fs,InputParams.NArray,InputParams.ArraySpacing,InputParams.TWindow,2);
P.fBeam = fBeam; P.SSP = SSP; P.Rd = InputParams.Rd; P.RecvRange = InputParams.RecvRange;
P.TowedArray = InputParams.TowedArray;
end

function f = sharedFrequencyForCompatibilityLocal(tx)
if isfield(tx,'fCW'), f=tx.fCW; else, f=(tx.fStart+tx.fEnd)/2; end
end
function pathOut = resolvePathLocal(pathIn,baseDir)
pathIn = char(pathIn);
if isempty(pathIn), pathOut=pathIn; return; end
if isAbsoluteLocal(pathIn), pathOut=pathIn; else, pathOut=fullfile(baseDir,pathIn); end
pathOut = char(java.io.File(pathOut).getCanonicalPath());
end
function tf = isAbsoluteLocal(p)
tf = ~isempty(regexp(p,'^[A-Za-z]:[\\/]|^\\\\','once'));
end
function value = fieldOrLocal(S,name,defaultValue)
if isstruct(S) && isfield(S,name) && ~isempty(S.(name)), value=S.(name); else, value=defaultValue; end
end
function value = requiredTextLocal(S,name,prefix)
if ~isfield(S,name) || strlength(string(S.(name)))==0, error('BuildInputParamsFromJson:MissingField','Missing %s.%s.',prefix,name); end
value=char(S.(name));
end
function value = requiredScalarLocal(S,name,prefix)
if ~isfield(S,name), error('BuildInputParamsFromJson:MissingField','Missing %s.%s.',prefix,name); end
value=double(S.(name)); validateattributes(value,{'numeric'},{'scalar','real','finite'});
end
function value = requiredPositiveLocal(S,name,prefix)
value=requiredScalarLocal(S,name,prefix); if value<=0, error('BuildInputParamsFromJson:InvalidValue','%s.%s must be >0.',prefix,name); end
end
function value = requiredNonnegativeLocal(S,name,prefix)
value=requiredScalarLocal(S,name,prefix); if value<0, error('BuildInputParamsFromJson:InvalidValue','%s.%s must be >=0.',prefix,name); end
end
function value = ternaryLocal(cond,a,b)
if cond, value=a; else, value=b; end
end
