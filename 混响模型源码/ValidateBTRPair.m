function Validation = ValidateBTRPair(Sim,Meas,Options)
%ValidateBTRPair Formal raw/metric BTR validation shared by App and scripts.
% BTR matrices are rows=scanAngles, columns=time. Display transforms are
% deliberately absent from this function.
if nargin<3 || isempty(Options),Options=struct();end
Params=GetDefaultBTRPeakValidationParams();
if isfield(Options,'Peak'),Params.Peak=mergeStructLocal(Params.Peak,Options.Peak);end
if isfield(Options,'Match'),Params.Match=mergeStructLocal(Params.Match,Options.Match);end
if isfield(Options,'PassThresholdSec')
    Params.PassThresholdSec=double(Options.PassThresholdSec);
    Params.Match.PassThreshold=Params.PassThresholdSec;
end
if isfield(Options,'EvalWindow') && numel(Options.EvalWindow)==2
    Params.Peak.TimeLimits=double(Options.EvalWindow(:).');
end

[simBTR,simTime,simAngles,simFs]=validateInputLocal(Sim,'Sim');
[measBTR,measTime,measAngles,measFs]=validateInputLocal(Meas,'Meas');
commonFs=min(simFs,measFs);
[simRate,simTimeRate]=resampleTimeLocal(simBTR,simTime,commonFs);
[measRate,measTimeRate]=resampleTimeLocal(measBTR,measTime,commonFs);

t0=max(simTimeRate(1),measTimeRate(1));
t1=min(simTimeRate(end),measTimeRate(end));
if ~(isfinite(t0)&&isfinite(t1)&&t1>t0)
    error('ValidateBTRPair:NoCommonTime','Simulation and measurement have no common time range.');
end
commonTime=(ceil(t0*commonFs):floor(t1*commonFs)).'/commonFs;
simTimeCommon=interp1(simTimeRate,simRate.',commonTime,'linear',NaN).';
measTimeCommon=interp1(measTimeRate,measRate.',commonTime,'linear',NaN).';

stepSim=angleStepLocal(simAngles);stepMeas=angleStepLocal(measAngles);
stepCommon=max(stepSim,stepMeas);
a0=max(min(simAngles),min(measAngles));a1=min(max(simAngles),max(measAngles));
if ~(isfinite(a0)&&isfinite(a1)&&a1>=a0)
    error('ValidateBTRPair:NoCommonAngles','Simulation and measurement have no common angle range.');
end
if ~isfinite(stepCommon)
    commonAngles=a0;
else
    commonAngles=a0:stepCommon:a1;
    if isempty(commonAngles),commonAngles=a0;end
end
simMetric=interp1(simAngles,simTimeCommon,commonAngles,'linear',NaN);
measMetric=interp1(measAngles,measTimeCommon,commonAngles,'linear',NaN);
simMetric=normalizeMetricLocal(simMetric);
measMetric=normalizeMetricLocal(measMetric);

Validation=struct();
Validation.Status='NOT_COMPUTED';
Validation.ReasonCode='NO_VALID_MATCH';
Validation.Pass=false;
Validation.EglobalSec=NaN;
Validation.EglobalMs=NaN;
Validation.MatchCount=0;
Validation.ValidBeamCount=0;
Validation.CommonFs=commonFs;
Validation.CommonTime=commonTime;
Validation.CommonAngles=commonAngles;
Validation.CommonAngleStepDeg=stepCommon;
Validation.SimMetric=simMetric;
Validation.MeasMetric=measMetric;
Validation.Params=Params;
Validation.PeakTableSim=table();Validation.PeakTableMeas=table();
Validation.ErrorTable=table();Validation.GlobalError=struct();

try
    [peakSim,infoSim]=ExtractBTRPeaks(simMetric,commonTime,commonAngles,Params.Peak);
    [peakMeas,infoMeas]=ExtractBTRPeaks(measMetric,commonTime,commonAngles,Params.Peak);
    Validation.PeakTableSim=peakSim;Validation.PeakTableMeas=peakMeas;
    Validation.PeakInfoSim=infoSim;Validation.PeakInfoMeas=infoMeas;
    if height(peakSim)==0 || height(peakMeas)==0
        Validation.Message='No peaks were extracted from one or both BTR matrices.';
        return;
    end
    [errors,globalError]=MatchBTRPeaks(peakSim,peakMeas,Params.Match);
    Validation.ErrorTable=errors;Validation.GlobalError=globalError;
    Validation.MatchCount=height(errors);
    if isfield(globalError,'NumMatchedBeams'),Validation.ValidBeamCount=globalError.NumMatchedBeams;end
    if height(errors)==0 || ~isfield(globalError,'Eglobal') || ~isfinite(globalError.Eglobal)
        Validation.Message='No valid interval-constrained peak matches.';
        return;
    end
    Validation.EglobalSec=double(globalError.Eglobal);
    Validation.EglobalMs=1000*Validation.EglobalSec;
    Validation.Pass=Validation.EglobalSec<=Params.PassThresholdSec;
    if Validation.Pass,Validation.Status='PASS';else,Validation.Status='FAIL';end
    Validation.ReasonCode='FORMAL_MATCH';
    Validation.Message=sprintf('Formal BTR peak match: Eglobal=%.3f ms, matches=%d.', ...
        Validation.EglobalMs,Validation.MatchCount);
catch ME
    Validation.Message=['Formal BTR validation was not computed: ' ME.message];
    Validation.ErrorIdentifier=ME.identifier;
end
end

function [B,t,a,fs]=validateInputLocal(S,label)
if ~isstruct(S)||~isfield(S,'BTR'),error('ValidateBTRPair:Input','%s.BTR is required.',label);end
B=double(S.BTR);t=double(readFieldLocal(S,{'timeBTR','timeAxis'}));a=double(readFieldLocal(S,{'scanAngles'}));
t=t(:);a=a(:).';
if size(B,1)~=numel(a)||size(B,2)~=numel(t)
    error('ValidateBTRPair:Orientation','%s BTR must be scanAngles-by-time.',label);
end
if numel(t)<2||any(diff(t)<=0)||numel(a)<1||any(diff(a)<=0)
    error('ValidateBTRPair:Axis','%s axes must be strictly increasing.',label);
end
fs=1/median(diff(t));
end
function value=readFieldLocal(S,names)
for k=1:numel(names),if isfield(S,names{k})&&~isempty(S.(names{k})),value=S.(names{k});return;end,end
error('ValidateBTRPair:MissingField','Missing required field: %s.',strjoin(names,'/'));
end
function [Bout,tout]=resampleTimeLocal(B,t,fsOut)
fsIn=1/median(diff(t));
if abs(fsIn-fsOut)<=1e-9*max(fsIn,fsOut),Bout=B;tout=t;return;end
[p,q]=rat(fsOut/fsIn,1e-10);
first=resample(B(1,:),p,q);
Bout=zeros(size(B,1),numel(first),'like',first);Bout(1,:)=first;
for r=2:size(B,1),Bout(r,:)=resample(B(r,:),p,q);end
tout=t(1)+(0:size(Bout,2)-1).'/fsOut;
valid=tout<=t(end)+0.5/fsOut;tout=tout(valid);Bout=Bout(:,valid);
end
function step=angleStepLocal(a)
if numel(a)<2,step=Inf;else,step=median(diff(a));end
end
function B=normalizeMetricLocal(B)
finite=isfinite(B);if ~any(finite(:)),B(:)=NaN;return;end
top=max(B(finite));B=B-top;B(~finite)=NaN;
end
function out=mergeStructLocal(base,extra)
out=base;if ~isstruct(extra),return;end
f=fieldnames(extra);for k=1:numel(f),out.(f{k})=extra.(f{k});end
end
