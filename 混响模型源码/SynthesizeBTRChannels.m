function [BTRVisible,BTRLinear,timeBTR,scanAngles,BTRInfo,BTRChannelInfo,BTRDisplay,BTRDisplayInfo] = SynthesizeBTRChannels(InputParams,Channels,ChannelResults)
if ~InputParams.NeedBTR
    BTRVisible=[];BTRLinear=[];timeBTR=[];scanAngles=[];BTRInfo=struct();BTRChannelInfo=[];
    BTRDisplay=[];BTRDisplayInfo=struct();return;
end
P=InputParams.BTRParams;fs=InputParams.fs;
in=struct('N',P.N,'d',P.d,'RecvRange',InputParams.RecvRange,'Rd',InputParams.Rd,'SSP',InputParams.SSP);
[G,validation]=BuildTowedArrayGeometry(InputParams,in);
if ~validation.Pass,error('SynthesizeBTRChannels:Geometry','Invalid receive geometry');end
files=cell(numel(Channels),1);
BTRChannelInfo=repmat(struct('ChannelIndex',0,'Name','','Frequency',0, ...
    'SignalStartTime',0,'BTRInfo',struct(),'LinearSize',[]),numel(Channels),1);
try
for ch=1:numel(Channels)
    internal=P;internal.ReturnOnDisk=true;
    [~,~,scanAngles,info,linear]=BTRfromEvents(ChannelResults(ch).EventTable,G,Channels(ch).TxWaveform,fs,internal);
    files{ch}=linear.DiskFile;
    BTRChannelInfo(ch)=struct('ChannelIndex',ch,'Name',Channels(ch).Name, ...
        'Frequency',Channels(ch).ReferenceFrequency,'SignalStartTime',Channels(ch).SignalStartTime, ...
        'BTRInfo',info,'LinearSize',[numel(scanAngles),ceil(P.TWindow*fs)+1]);
end
% Channel start times are preserved before power, smoothing and rate change.
nInternal=ceil(P.TWindow*fs)+1;nOut=ceil(P.TWindow*P.BTRFs)+1;
timeBTR=(0:nOut-1)/P.BTRFs;BTRVisible=zeros(numel(scanAngles),nOut,'single');
[p,q]=rat(P.BTRFs/fs,1e-10);smoothPts=max(1,round(P.SmoothTime*fs));
% BTRDisplay is a calibrated complex pressure product.  Keep it on disk so
% high-rate beam x pressure-time matrices never have to reside in memory.
displayFile=fullfile(InputParams.OutputPath,'BTRDisplay.mat');
if ~exist(InputParams.OutputPath,'dir'),mkdir(InputParams.OutputPath);end
if isfile(displayFile),delete(displayFile);end
displayStore=matfile(displayFile,'Writable',true);
displayStore.BTRDisplay(numel(scanAngles),nInternal)=complex(single(0));
timeBTRDisplay=(0:nInternal-1)/fs;
scanAnglesDisplay=double(scanAngles(:).')+90;
displayStore.timeBTRDisplay=timeBTRDisplay;
displayStore.scanAngles=scanAnglesDisplay;
displayStore.AngleConvention='theta_0_180_array_axis_deg';
displayStore.MatrixOrientation='rows=scanAngles, columns=timeBTRDisplay';
sourceScale_uPa=10^(double(InputParams.SourceLevel)/20);
receiverGain_V_per_uPa=10^((double(InputParams.Sensitivity)+double(InputParams.AmpGain))/20);
if ~isfinite(sourceScale_uPa)||sourceScale_uPa<=0||~isfinite(receiverGain_V_per_uPa)||receiverGain_V_per_uPa<=0
    error('SynthesizeBTRChannels:Calibration','Invalid source or receiver calibration.');
end
noiseSeeds=zeros(numel(scanAngles),1,'uint32');
diagnostic=isfield(InputParams,'BTRDiagnosticDir') && ~isempty(InputParams.BTRDiagnosticDir);
if diagnostic
    folder=InputParams.BTRDiagnosticDir;if ~exist(folder,'dir'),mkdir(folder);end
    high=matfile(fullfile(folder,'BTRHighRes.mat'),'Writable',true);
    high.yBTR(numel(scanAngles),nInternal)=complex(single(0));
    high.fs=fs;high.scanAngles=scanAngles;
end
for a=1:numel(scanAngles)
    y=complex(zeros(1,nInternal,'single'));
    for ch=1:numel(Channels)
        d=matfile(files{ch});v=d.yBTR(:,a).';
        start=Channels(ch).SignalStartTime*fs;
        if abs(start-round(start))>1e-8
            F=fft(v,2^nextpow2(2*numel(v)));
            f=(0:numel(F)-1)/numel(F);f(f>0.5)=f(f>0.5)-1;
            v=ifft(F.*single(exp(-2i*pi*f*(start-floor(start)))));v=v(1:nInternal);
        end
        first=floor(start)+1;count=nInternal-first+1;
        if count>0,y(first:end)=y(first:end)+v(1:count);end
    end
    if diagnostic,high.yBTR(a,:)=y;end
    % y is the wideband complex-linear beam pressure transfer before abs(.)^2.
    % Generate one reproducible receiver-noise realization per beam.  The
    % approved spatial model is white in beam space: Cov(n)=sigma^2*I.
    seed=uint32(mod(20261009+104729*(a-1),2^32-1));
    noiseSeeds(a)=seed;
    [vNoise,~,~]=BuildFluctuatingEnvironmentalNoise(nInternal,fs, ...
        double(InputParams.NL),double(InputParams.Sensitivity), ...
        double(InputParams.AmpGain),3.5,double(seed));
    pNoise=analyticAlongTimeLocal(double(vNoise(:).'))/receiverGain_V_per_uPa;
    pDisplay=double(y)*sourceScale_uPa+pNoise;
    displayStore.BTRDisplay(a,1:nInternal)=complex(single(pDisplay));
    power=movmean(abs(y).^2,smoothPts,2);
    output=max(0,resample(double(power),p,q));
    count=min(nOut,numel(output));BTRVisible(a,1:count)=single(10*log10(max(output(1:count),realmin('double'))));
end
if P.NormalizeDB,BTRVisible=BTRVisible-max(BTRVisible(:));end
BTRLinear=[];
BTRDisplay=struct('Storage','chunked_matfile','File',displayFile, ...
    'Dataset','BTRDisplay','Size',[numel(scanAngles),nInternal], ...
    'CaseDimension','one file per Tx steering case');
pitchUser=0;
if isfield(InputParams,'RxArrayPitchDeg_User')
    pitchUser=InputParams.RxArrayPitchDeg_User;
elseif isfield(InputParams,'TowedArray')&&isfield(InputParams.TowedArray,'UserPitchDeg')
    pitchUser=InputParams.TowedArray.UserPitchDeg;
end
BTRInfo=struct('CombinationDomain','complex_linear_time_before_power', ...
    'SmoothPoints',smoothPts,'SmoothTime',P.SmoothTime,'ProcessingFs',fs,'BTRFs',P.BTRFs, ...
    'NormalizeDB',P.NormalizeDB,'MatrixOrientation','rows=scanAngles, columns=time', ...
    'NumChannels',numel(Channels),'Size',size(BTRVisible),'PhaseMode','full_3D_HLA', ...
    'ApplyElementDelay',true,'SteeringMode',P.SteeringMode, ...
    'BeamformingModel','wideband_true_time_delay_frequency_steering', ...
    'InternalAngleConvention','beta_-90_90_broadside_deg', ...
    'ReceiverPitchDegUser',pitchUser,'InternalPitchDeg',G.PitchDeg, ...
    'ArrayGeometry',G,'GeometryValidation',validation, ...
    'PeakWorkingMemoryEstimate',max(arrayfun(@(x)x.BTRInfo.PeakWorkingMemoryEstimate,BTRChannelInfo)), ...
    'ProcessingTime',sum(arrayfun(@(x)x.BTRInfo.ProcessingTime,BTRChannelInfo)));
includeDirect=false;if isfield(P,'IncludeDirect'),includeDirect=logical(P.IncludeDirect);end
BTRDisplayInfo=struct('PhysicalQuantity','complex analytic pressure', ...
    'Units','uPa','CombinationDomain','complex_linear_time_before_power', ...
    'SourceLevelAppliedOnce_dB_re_1uPa',double(InputParams.SourceLevel), ...
    'ReceiverSensitivity_dB_re_1V_per_uPa',double(InputParams.Sensitivity), ...
    'ReceiverAmpGain_dB',double(InputParams.AmpGain), ...
    'ReceiverGain_V_per_uPa',receiverGain_V_per_uPa, ...
    'NoiseLevel_dB_re_1uPa',double(InputParams.NL), ...
    'NoiseJitterStd_dB',3.5,'NoiseSpatialCovariance','identity_in_beam_domain', ...
    'NoiseSeedPolicy','seed=mod(20261009+104729*(beamIndex-1),2^32-1)', ...
    'NoiseSeeds',noiseSeeds,'IncludeDirect',includeDirect, ...
    'PressureFsHz',fs,'PowerDisplayFsHz',P.BTRFs, ...
    'TimeAxisDataset','timeBTRDisplay','PowerTimeAxis','timeBTR', ...
    'File',displayFile,'Dataset','BTRDisplay','Size',[numel(scanAngles),nInternal]);
displayStore.BTRDisplayInfo=BTRDisplayInfo;
catch ME
    deleteFilesLocal(files);rethrow(ME);
end
deleteFilesLocal(files);
end
function z=analyticAlongTimeLocal(x)
n=numel(x);X=fft(x,n,2);h=zeros(1,n);
if mod(n,2)==0,h([1 n/2+1])=1;h(2:n/2)=2;else,h(1)=1;h(2:(n+1)/2)=2;end
z=ifft(X.*h,n,2);
end
function deleteFilesLocal(files)
for k=1:numel(files),if ~isempty(files{k}) && isfile(files{k}),delete(files{k});end,end
end
