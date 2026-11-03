function [Response,Audit] = ApplyPaperObservation20msToSideResponses(hTotal,hPlus,hMinus,hAxis,fs)
%ApplyPaperObservation20msToSideResponses Common 20-ms operator for all sides.
arguments
    hTotal {mustBeNumeric}
    hPlus {mustBeNumeric}
    hMinus {mustBeNumeric}
    hAxis {mustBeNumeric}
    fs (1,1) double {mustBeFinite,mustBePositive}
end
n=numel(hTotal);assert(numel(hPlus)==n&&numel(hMinus)==n&&numel(hAxis)==n,'P20:SideLengthMismatch');
[zTotal,a0]=ApplyPaperObservation20ms(hTotal,fs);
[zPlus,ap]=ApplyPaperObservation20ms(hPlus,fs);
[zMinus,am]=ApplyPaperObservation20ms(hMinus,fs);
[zAxis,aa]=ApplyPaperObservation20ms(hAxis,fs);
zPartition=zPlus+zMinus+zAxis;
err=zTotal-zPartition;
t=(0:numel(zTotal)-1)'/fs;
Audit=struct('ContractVersion','P20_SIDE_OBSERVER_v1', ...
    'CommonOperatorAllComponents',true,'PerComponentPulseApplicationCount',1, ...
    'EventTraversalCount',0,'StageBMaxAbsClosure',max(abs(err)), ...
    'StageBRelativeL2Closure',norm(err)/max(norm(zTotal),eps), ...
    'TotalAudit',a0,'PlusAudit',ap,'MinusAudit',am,'AxisAudit',aa);
Response=struct('t',t,'zTotal',zTotal,'zPlus',zPlus,'zMinus',zMinus, ...
    'zAxis',zAxis,'zPartition',zPartition);
end
