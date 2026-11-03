function [RunSummary,outputFiles] = SaveZSDXOutputs(Results,InputParams,cfg,resolved)
%SaveZSDXOutputs Save fixed metadata plus selected time/BTR products.
out=InputParams.OutputPath; if ~exist(out,'dir'), mkdir(out); end
inputConfigFile=fullfile(out,'InputConfig.json'); WriteJsonUtf8(inputConfigFile,cfg);
outputFiles={inputConfigFile}; selection=InputParams.OutputSelection;

timeRt=Results.timeRt; yTotal=Results.yTotal;
yDir=Results.yDir; ySca=Results.ySca;
if ismember(1,selection)
    f=figure('Visible','off'); plot(timeRt,real(yTotal)); grid on;
    xlabel('Time / s'); ylabel('Real voltage'); title('ZSDX Time Response');
    xlim([timeRt(1) timeRt(end)]); peak=max(abs(real(yTotal(:))));
    if peak>0, ylim([-peak peak]); end
    file=fullfile(out,'TimeResponse.fig'); savefig(f,file); close(f); outputFiles{end+1}=file;
end
if ismember(2,selection)
    file=fullfile(out,'TimeResponse.bin');
    writeTimeBinLocal(file,timeRt,yTotal);
    outputFiles{end+1}=file;
end
if ismember(3,selection)
    file=fullfile(out,'TimeResponse.mat');
    save(file,'timeRt','yTotal','-v7.3');
    outputFiles{end+1}=file;
end

BTR=Results.BTRVisible; timeBTR=Results.timeBTR;
scanAnglesBeta=double(Results.scanAngles(:).');
if any(scanAnglesBeta < -90-1e-9 | scanAnglesBeta > 90+1e-9)
    error('SaveZSDXOutputs:InternalAngleRange','Internal BTR beta angles must lie in [-90,90].');
end
scanAngles=scanAnglesBeta+90;
AngleConvention='theta_0_180_array_axis_deg'; %#ok<NASGU>
matrixOrientation='rows=scanAngles, columns=timeBTR'; %#ok<NASGU>
if ismember(4,selection)
    f=figure('Visible','off'); ax=axes(f); img=imagesc(ax,scanAngles,timeBTR,BTR.'); axis(ax,'xy');
    img.UserData=struct('Schema','ReverbBTRFigureV3','RawBTR',BTR, ...
        'timeBTR',timeBTR,'scanAngles',scanAngles, ...
        'AngleConvention',AngleConvention,'RawScale','dB', ...
        'MatrixLayout','angle_by_time','DisplayMatrixLayout','time_by_angle');
    colormap(ax,jet(256)); clim(ax,[-50 0]); pbaspect(ax,[3 4 1]); colorbar(ax);
    xlabel('Array-axis angle theta / deg'); ylabel('Time / s'); title('Beam-Time Response');
    file=fullfile(out,'BTR.fig'); savefig(f,file); close(f); outputFiles{end+1}=file;
end
if ismember(5,selection)
    file=fullfile(out,'BTR.mat');
    save(file,'BTR','timeBTR','scanAngles','AngleConvention','matrixOrientation','-v7.3');
    outputFiles{end+1}=file;
end
if isfield(Results,'BTRDisplay') && isstruct(Results.BTRDisplay) && ...
        isfield(Results.BTRDisplay,'File') && isfile(Results.BTRDisplay.File)
    outputFiles{end+1}=Results.BTRDisplay.File;
end

% readZSDX runs in a separate MATLAB process from the deployed EXE.  Return
% only the requested numeric arrays through a short-lived binary cache.
% readZSDX reads this file into MATLAB doubles and deletes it immediately.
if isfield(InputParams,'ReturnToCaller') && InputParams.ReturnToCaller
    returnFile=fullfile(out,'RuntimeReturn.tmp');
    fprintf('Writing lightweight in-memory return cache.\n');
    writeRuntimeReturnLocal(returnFile,timeRt,yTotal,yDir,ySca, ...
        timeBTR,scanAngles,BTR,Results.PublicDisplay);
    fprintf('Lightweight in-memory return cache complete.\n');
end

outputFiles{end+1}=fullfile(out,'CallResult.json');
channelSummary=channelSummaryLocal(Results);
btrDisplay=struct();btrDisplayInfo=struct();
if isfield(Results,'BTRDisplay'),btrDisplay=Results.BTRDisplay;end
if isfield(Results,'BTRDisplayInfo'),btrDisplayInfo=Results.BTRDisplayInfo;end
RunSummary=struct('ok',true,'message','completed','warnings',{resolved.warnings}, ...
    'inputJson',InputParams.InputJson,'outputPath',out,'appliedConfig',cfg, ...
    'frequencyChannelStrategy',Results.FrequencyChannels(1).ModeApplied, ...
    'frequencyChannelDecision',Results.FrequencyChannels(1).DecisionReason, ...
    'frequencyChannelCount',numel(Results.FrequencyChannels), ...
    'frequencyChannels',channelSummary,'bellhopJobs',Results.PropagationInfo.BellhopJobs, ...
    'bellhopJobCountExpected',Results.PropagationInfo.BellhopJobCountExpected, ...
    'bellhopJobCountActual',Results.PropagationInfo.BellhopJobCountActual, ...
    'bellhopDispatch',Results.PropagationInfo.BellhopDispatch, ...
    'scatterParallel',Results.PropagationInfo.ScatterParallel, ...
    'beamResolved',resolved.beamResolved, ...
    'beamComputationBoost',resolved.beamComputationBoost, ...
    'bottomResolved',resolved.bottomResolved, ...
    'scatteringResolved',resolved.scatteringResolved,'surfaceResolved',resolved.surfaceResolved, ...
    'sspResolved',resolved.sspResolved, ...
    'btrForcedByOutputSelection',resolved.btrForcedByOutputSelection, ...
    'timeCost',Results.TimeCost,'resultDiagnostics',Results.ResultDiagnostics, ...
    'btrProcessing',Results.BTRInfo,'btrChannels',Results.BTRChannelInfo, ...
    'btrDisplay',btrDisplay,'btrDisplayInfo',btrDisplayInfo, ...
    'btrPublicAngleConvention','theta_0_180_array_axis_deg', ...
    'btrInternalAngleConvention','beta_-90_90_broadside_deg', ...
    'outputFiles',{outputFiles});
RunSummary.pressureInfo=Results.PublicDisplay.PressureInfo;
RunSummary.displayNoiseAudit=Results.PublicDisplay.NoiseAudit;
RunSummary.runtimeReturnVersion=3;
summaryFile=fullfile(out,'RunSummary.json'); WriteJsonUtf8(summaryFile,RunSummary); outputFiles{end+1}=summaryFile;
RunSummary.outputFiles=outputFiles; WriteJsonUtf8(summaryFile,RunSummary);
end

function writeTimeBinLocal(fileName,timeRt,yTotal)
fid=fopen(fileName,'w','ieee-le'); if fid<0, error('SaveZSDXOutputs:OpenBin','Cannot write %s.',fileName); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
payload=[double(timeRt(:)).';double(yTotal(:)).'];
interleaved=[real(payload(:)).';imag(payload(:)).'];
fwrite(fid,interleaved,'double');
end
function writeRuntimeReturnLocal(fileName,timeRt,yTotal,yDir,ySca,timeBTR,scanAngles,BTR,publicDisplay)
fid=fopen(fileName,'w','ieee-le');
if fid<0, error('SaveZSDXOutputs:OpenReturnCache','Cannot write %s.',fileName); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,uint8('ZSDXRET1'),'uint8');
fwrite(fid,uint32(3),'uint32');
nTime=uint64(numel(timeRt));
nBtrTime=uint64(numel(timeBTR));
nAngles=uint64(numel(scanAngles));
fwrite(fid,[nTime nBtrTime nAngles],'uint64');
writeRealLocal(fid,timeRt);
writeComplexLocal(fid,yTotal);
writeComplexLocal(fid,yDir);
writeComplexLocal(fid,ySca);
writeRealLocal(fid,timeBTR);
writeRealLocal(fid,scanAngles);
writeRealLocal(fid,BTR);
writeComplexLocal(fid,publicDisplay.Pressure);
writeRealLocal(fid,publicDisplay.RL);
writeRealLocal(fid,publicDisplay.Voltage);
end
function writeRealLocal(fid,value)
fwrite(fid,double(value(:)),'double');
end
function writeComplexLocal(fid,value)
value=value(:);
fwrite(fid,double(real(value)),'double');
fwrite(fid,double(imag(value)),'double');
end
function summary=channelSummaryLocal(Results)
n=numel(Results.FrequencyChannels);
summary=repmat(struct('index',0,'name','','referenceFrequency',0,'signalType','', ...
    'signalStartTime',0,'signalDuration',0,'hDirSize',[],'hScaSize',[], ...
    'yDirSize',[],'yScaSize',[],'eventCount',0),n,1);
for k=1:n
    c=Results.FrequencyChannels(k); r=Results.ChannelResults(k);
    summary(k).index=k; summary(k).name=c.Name; summary(k).referenceFrequency=c.ReferenceFrequency;
    summary(k).signalType=c.SignalType; summary(k).signalStartTime=c.SignalStartTime; summary(k).signalDuration=c.SignalDuration;
    summary(k).hDirSize=size(r.hDir); summary(k).hScaSize=size(r.hSca);
    summary(k).yDirSize=size(r.yDirComponent); summary(k).yScaSize=size(r.yScaComponent);
    if istable(r.EventTable),summary(k).eventCount=height(r.EventTable);else,summary(k).eventCount=numel(r.EventTable);end
end
end
