function ZSDXReverbExeMain(jsonFile)
%#exclude bandpass
%ZSDXReverbExeMain Compiled JSON console entry point.
% The JSON entry never passes NoiseBandHz options to the noise helper.
% Exclude that unreachable optional filter-design dependency from this EXE;
% the shared noise helper and its MATLAB numerical behavior remain intact.
% A normal JSON runs one case.  readZSDX adds the internal
% Runtime.ThetaBatch object so one deployed process can run all requested
% steering angles while reusing the same MATLAB parallel pool.
if nargin<1 || isempty(jsonFile)
    error('ZSDXReverbExeMain:MissingJson','Usage: ZSDXReverb.exe <case.json>');
end
jsonFile=char(jsonFile);
if ~isfile(jsonFile)
    error('ZSDXReverbExeMain:JsonNotFound','JSON file not found: %s',jsonFile);
end

cfg=[];
outputPath=fileparts(jsonFile);
isBatch=false;
try
    cfg=ReadJsonUtf8(jsonFile);
    cfg=resolveBundledInputAssetsLocal(cfg,jsonFile);
    isBatch=isThetaBatchLocal(cfg);
    if isBatch
        outputPath=resolveBatchRootLocal(cfg.Runtime.ThetaBatch,jsonFile);
        callResult=runThetaBatchLocal(cfg,jsonFile,outputPath);
    else
        [callResult,~]=runOneCaseLocal(cfg,jsonFile);
        outputPath=callResult.outputPath;
    end
    disp(jsonencode(callResult));
catch ME
    if ~isempty(cfg)
        try
            if isBatch
                outputPath=resolveBatchRootLocal(cfg.Runtime.ThetaBatch,jsonFile);
            elseif isfield(cfg,'File') && isfield(cfg.File,'outputPath')
                outputPath=resolveOutputPathLocal(cfg.File.outputPath,jsonFile);
            end
        catch
        end
    end
    try
        if ~exist(outputPath,'dir'), mkdir(outputPath); end
        failure=struct('ok',false,'message',ME.message,'identifier',ME.identifier, ...
            'inputJson',jsonFile,'outputPath',outputPath);
        if isBatch
            failureFile=fullfile(outputPath,'BatchCallResult.json');
        else
            failureFile=fullfile(outputPath,'CallResult.json');
        end
        WriteJsonUtf8(failureFile,failure);
        disp(jsonencode(failure));
    catch
    end
    rethrow(ME);
end
end

function tf=isThetaBatchLocal(cfg)
tf=isstruct(cfg) && isfield(cfg,'Runtime') && isstruct(cfg.Runtime) && ...
    isfield(cfg.Runtime,'ThetaBatch') && isstruct(cfg.Runtime.ThetaBatch);
end

function batchResult=runThetaBatchLocal(cfg,batchJsonFile,runRoot)
batch=cfg.Runtime.ThetaBatch;
if ~isfield(batch,'thetaList') || isempty(batch.thetaList)
    error('ZSDXReverbExeMain:MissingThetaList', ...
        'Runtime.ThetaBatch.thetaList must contain at least one angle.');
end
thetaList=double(batch.thetaList(:).');
validateattributes(thetaList,{'numeric'},{'real','finite','nonempty'});
if ~isfield(cfg,'Beam') || ~isfield(cfg.Beam,'ArrayType')
    error('ZSDXReverbExeMain:MissingArrayType','Missing Beam.ArrayType.');
end
arrayType=double(cfg.Beam.ArrayType);
if ~ismember(arrayType,[1 2 3 4])
    error('ZSDXReverbExeMain:UnsupportedBatchArrayType', ...
        'Theta batch supports Beam.ArrayType 1, 2, 3, or fixed custom type 4.');
end
if arrayType==4 && numel(thetaList)~=1
    error('ZSDXReverbExeMain:CustomBeamSingleCase', ...
        'Beam.ArrayType=4 is fixed and supports exactly one batch case.');
end

if ~exist(runRoot,'dir'), mkdir(runRoot); end
caseResults=cell(numel(thetaList),1);
fprintf('[ZSDXReverb batch] One EXE will run %d theta case(s) sequentially.\n',numel(thetaList));

for k=1:numel(thetaList)
    caseDir=fullfile(runRoot,sprintf('theta_%04d',k));
    outDir=fullfile(caseDir,'output');
    tempDir=fullfile(caseDir,'temp');
    if ~exist(outDir,'dir'), mkdir(outDir); end
    if ~exist(tempDir,'dir'), mkdir(tempDir); end

    caseCfg=cfg;
    caseCfg.Runtime=rmfield(caseCfg.Runtime,'ThetaBatch');
    caseCfg=setArrayThetaLocal(caseCfg,arrayType,thetaList(k));
    caseCfg.File.outputPath=slashLocal(outDir);
    caseCfg.Runtime.TempWorkDir=slashLocal(tempDir);
    caseCfg.Runtime.ReturnToCaller=true;

    caseJson=fullfile(caseDir,'case_readZSDX.json');
    WriteJsonUtf8(caseJson,caseCfg);

    % Two stable console lines for external capture; no progress-file protocol.
    fprintf('theta = %g deg.\n',thetaList(k));
    fprintf('当前指向角：%g 度\n',thetaList(k));
    try
        [caseResults{k},summary]=runOneCaseLocal(caseCfg,caseJson,k,thetaList(k));
    catch ME
        error('ZSDXReverbExeMain:ThetaCaseFailed', ...
            'Theta case %d/%d (%g deg) failed: %s', ...
            k,numel(thetaList),thetaList(k),ME.message);
    end
    fprintf(['[ZSDXReverb batch] Completed theta = %g deg: ' ...
        'BELLHOP=%d/%d, mainBeam=%s, elevSide=%s/%s dB, ' ...
        'azMain=%s, azSide=%s/%s dB.\n'], ...
        thetaList(k),summary.bellhopJobCountActual, ...
        summary.bellhopJobCountExpected,mat2str(summary.beamResolved.MainBeam), ...
        mat2str(summary.beamResolved.SideRange), ...
        mat2str(summary.beamResolved.SideDown_dB), ...
        mat2str(summary.beamResolved.AzimuthRange), ...
        mat2str(summary.beamResolved.AzimuthSideRange), ...
        mat2str(summary.beamResolved.AzimuthSideDown_dB));
end

batchResult=struct('ok',true,'message','theta batch completed', ...
    'inputJson',batchJsonFile,'outputPath',runRoot, ...
    'arrayType',arrayType,'thetaList',thetaList,'caseCount',numel(thetaList));
batchResult.cases=caseResults;
WriteJsonUtf8(fullfile(runRoot,'BatchCallResult.json'),batchResult);
end

function [callResult,RunSummary]=runOneCaseLocal(cfg,jsonFile,caseIndex,displayTheta)
if nargin<3,caseIndex=1;end
if nargin<4,displayTheta=resolveDisplayThetaLocal(cfg);end
[InputParams,resolved,cfgApplied]=BuildInputParamsFromJson(cfg,jsonFile);
printBeamBoostAuditLocal(InputParams.BeamComputeAudit);
outputPath=InputParams.OutputPath;
Results=RunReverbSimulation(InputParams,InputParams.OptionBorder,InputParams.RunMode,[]);
% Display/output postprocessing stays separate from frozen clean scientific Results.
[vTotalNoisy,RLDisplay,noiseAudit]=ComputeNoisyDisplayFromBeamResponses( ...
    Results.yDir(:).',Results.ySca(:).',cfgApplied,displayTheta,caseIndex);
gRx=10^((double(cfgApplied.Intensity.sensitivity)+double(cfgApplied.Intensity.ampGain))/20);
validateattributes(gRx,{'numeric'},{'scalar','real','finite','positive'});
pDisplay=hilbert(double(vTotalNoisy(:))).' ./ gRx;
pressureInfo=struct('Units','uPa','ReceiverGain_V_per_uPa',gRx, ...
    'SourceLevel_dB_re_1uPa',double(cfgApplied.Intensity.sourceLevel), ...
    'Sensitivity_dB_re_1V_per_uPa',double(cfgApplied.Intensity.sensitivity), ...
    'AmpGain_dB',double(cfgApplied.Intensity.ampGain), ...
    'Construction','Hilbert analytic signal along dimension 2 divided by ReceiverGain_V_per_uPa', ...
    'TimeDimension',2, ...
    'ImaginaryPartMeaning','Hilbert quadrature; not an independent measured pressure channel');
Results.PublicDisplay=struct('Pressure',pDisplay,'RL',RLDisplay, ...
    'Voltage',vTotalNoisy,'PressureInfo',pressureInfo,'NoiseAudit',noiseAudit);
[RunSummary,files]=SaveZSDXOutputs(Results,InputParams,cfgApplied,resolved);
callResult=struct('ok',true,'message','completed','inputJson',jsonFile, ...
    'outputPath',outputPath,'runSummary',fullfile(outputPath,'RunSummary.json'),'files',{files});
WriteJsonUtf8(fullfile(outputPath,'CallResult.json'),callResult);
end

function printBeamBoostAuditLocal(audit)
if isfield(audit,'Applied') && ~audit.Applied
    fprintf('Residual sidelobe computation boost disabled; BeamCompute == BeamDisplay.\n');
    return;
end
fprintf('Residual sidelobe computation boost = +%.1f dB; changed entries = %d.\n', ...
    audit.BoostDB,audit.NumChangedEntries);
for k=1:numel(audit.Changes)
    c=audit.Changes(k);
    fprintf('  %s: nominal %s dB -> effective %s dB.\n', ...
        c.Path,mat2str(c.OldDB),mat2str(c.NewDB));
end
end

function cfg=setArrayThetaLocal(cfg,arrayType,thetaDeg)
switch arrayType
    case 1
        cfg.Beam.verticalArray.thetaDeg=thetaDeg;
    case 2
        cfg.Beam.horiArray.phiDeg=thetaDeg;
    case 3
        cfg.Beam.cylinArray.thetaDeg=thetaDeg;
    case 4
        % 固定自定义波束不接受外部指向角；保留JSON中的全向范围。
    otherwise
        error('ZSDXReverbExeMain:UnsupportedBatchArrayType', ...
            'Theta batch supports Beam.ArrayType 1, 2, 3, or fixed custom type 4.');
end
end

function runRoot=resolveBatchRootLocal(batch,jsonFile)
if ~isfield(batch,'runRoot') || strlength(string(batch.runRoot))==0
    error('ZSDXReverbExeMain:MissingBatchRoot', ...
        'Runtime.ThetaBatch.runRoot is required.');
end
runRoot=resolveOutputPathLocal(batch.runRoot,jsonFile);
end

function value=resolveOutputPathLocal(value,jsonFile)
value=char(value);
if isempty(regexp(value,'^[A-Za-z]:[\\/]|^\\\\','once'))
    value=fullfile(fileparts(jsonFile),value);
end
value=char(java.io.File(value).getCanonicalPath());
end

function p=slashLocal(p)
p=strrep(char(p),'\','/');
end

function theta=resolveDisplayThetaLocal(cfg)
switch double(cfg.Beam.ArrayType)
    case 1,theta=double(cfg.Beam.verticalArray.thetaDeg);
    case 2,theta=double(cfg.Beam.horiArray.phiDeg);
    case 3,theta=double(cfg.Beam.cylinArray.thetaDeg);
    otherwise,theta=0;
end
end

function cfg=resolveBundledInputAssetsLocal(cfg,jsonFile)
% Present user input wins. Known bundled resources are a fallback for a portable EXE.
if ~isdeployed,return;end
roots={fileparts(mfilename('fullpath')),ctfroot};
items={'Environment','sspPath','env';'Signal','customPath','signals'};
for k=1:size(items,1)
    group=items{k,1};field=items{k,2};folder=items{k,3};
    if ~isfield(cfg,group)||~isfield(cfg.(group),field)||isempty(cfg.(group).(field)),continue;end
    value=char(cfg.(group).(field));
    if isfile(value)||isfile(fullfile(fileparts(jsonFile),value)),continue;end
    [~,stem,ext]=fileparts(value);
    for n=1:numel(roots)
        candidate=fullfile(roots{n},folder,[stem ext]);
        if isfile(candidate)
            cfg.(group).(field)=strrep(candidate,'\','/');
            fprintf('Using bundled %s asset: %s\n',group,candidate);
            break;
        end
    end
end
end
