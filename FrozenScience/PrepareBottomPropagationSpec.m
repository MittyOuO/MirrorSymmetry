function PropagationSpec=PrepareBottomPropagationSpec(Domain,recvRangeM,profile)
%PrepareBottomPropagationSpec Fully resolve all three .env range contracts.
% ResetEnvBottom receives only this completed writer specification and never
% infers canonical/legacy behavior from input types or optional fields.

if nargin<3 || isempty(profile)
    if strcmpi(Domain.InputConvention,'canonical'), profile='formal'; else, profile='legacy_single'; end
end
profile=lower(strtrim(char(string(profile))));
recvRangeM=positiveScalarLocal(recvRangeM,'recvRangeM');
angleStep=positiveScalarLocal(Domain.BellhopLaunchAngleStepDeg,'BellhopLaunchAngleStepDeg');

switch profile
    case 'formal'
        if ~strcmpi(Domain.InputConvention,'canonical') || ~Domain.PaperEligible
            error('G3:FormalSpecRequiresCanonical','Formal propagation spec requires canonical paper-eligible domain.');
        end
        if abs(Domain.BellhopRangeStepM-1)>32*eps
            error('G3:FormalRangeStepLockedAt1m', ...
                'Paper-eligible S0-D requires BellhopRangeStepM = 1 m.');
        end
        stoB=completeFormalLocal(Domain.SourceToBottomSpec,'StoB');
        btoR=completeFormalLocal(Domain.BottomToReceiverSpec,'BtoR');
        stoR=completeDirectLocal(Domain.SourceToReceiverSpec,recvRangeM, ...
            ceil(recvRangeM/1000)+1,'%.9f %.9f  /  \t ! R(1:NR ) (km) \n');
        paperEligible=true;

    case {'legacy_single','legacy_fast_rl'}
        rangeMaxM=max([60000,recvRangeM,1000]);
        [stoB,btoR,stoR]=legacySpecsLocal(rangeMaxM,recvRangeM);
        paperEligible=false;

    case 'legacy_channels'
        rangeMaxM=max([double(Domain.RmaxM),recvRangeM,1000]);
        [stoB,btoR,stoR]=legacySpecsLocal(rangeMaxM,recvRangeM);
        paperEligible=false;

    otherwise
        error('G3:UnknownPropagationProfile','Unknown propagation profile: %s.',profile);
end

PropagationSpec=struct('Profile',profile,'PaperEligible',paperEligible, ...
    'ExplicitlyResolved',true,'SourceToBottom',stoB,'BottomToReceiver',btoR, ...
    'SourceToReceiver',stoR,'LaunchAngleStepDeg',angleStep, ...
    'WriterContractVersion',1);
end

function S=completeFormalLocal(S,pathName)
assert(abs(S.ActualRangeStepM-1)<=32*eps,'G3:FormalRangeStepLockedAt1m', ...
    '%s actual range step must equal 1 m.',pathName);
S.RangesM=[0,double(S.EnvRangeMaxM)];
S.RangeLineFormat='%.9f %.9f    /  \t ! R(1:NR ) (km) \n';
S.PathName=pathName;
end

function S=completeDirectLocal(S,recvRangeM,rBoxKm,format)
S.FormulaRangeMaxM=recvRangeM; S.EnvRangeMaxM=recvRangeM;
S.RequestedRangeStepM=NaN; S.ActualRangeStepM=recvRangeM;
S.NRange=2; S.RangeStepApplied=false; S.OverCoverageM=0;
S.RBoxKm=rBoxKm; S.RangesM=[0,recvRangeM]; S.RangeLineFormat=format;
S.PathName='StoR';
end

function [stoB,btoR,stoR]=legacySpecsLocal(rangeMaxM,recvRangeM)
nRange=ceil(rangeMaxM)+1; actual=rangeMaxM/(nRange-1); rBox=ceil(rangeMaxM/1000)+1;
base=struct('FormulaRangeMaxM',rangeMaxM,'EnvRangeMaxM',rangeMaxM, ...
    'RequestedRangeStepM',1,'ActualRangeStepM',actual,'NRange',nRange, ...
    'RangeStepApplied',true,'OverCoverageM',0,'RBoxKm',rBox, ...
    'RangesM',[0,rangeMaxM], ...
    'RangeLineFormat','%4.2f %6.2f    /  \t ! R(1:NR ) (km) \n','PathName','');
stoB=base; stoB.PathName='StoB'; btoR=base; btoR.PathName='BtoR';
directBase=struct('FormulaRangeMaxM',recvRangeM,'EnvRangeMaxM',recvRangeM, ...
    'RequestedRangeStepM',NaN,'ActualRangeStepM',recvRangeM,'NRange',2, ...
    'RangeStepApplied',false,'OverCoverageM',0,'RBoxKm',rBox);
stoR=completeDirectLocal(directBase,recvRangeM,rBox, ...
    '%4.3f %6.3f  /  \t ! R(1:NR ) (km) \n');
end

function value=positiveScalarLocal(value,name)
value=double(value);
if ~isscalar(value)||~isreal(value)||~isfinite(value)||value<=0
    error('G3:InvalidPositiveScalar','%s must be a finite positive scalar.',name);
end
end
