function Spec = BuildBellhopRangeSpec(formulaRangeMaxM, rangeStepM, pathType)
%BuildBellhopRangeSpec Build one path-specific BELLHOP range specification.

formulaRangeMaxM = positiveScalarLocal(formulaRangeMaxM,'formulaRangeMaxM');
pathType = lower(strtrim(char(string(pathType))));

if strcmp(pathType,'source_to_receiver')
    Spec = struct('PathType',pathType,'FormulaRangeMaxM',formulaRangeMaxM, ...
        'EnvRangeMaxM',formulaRangeMaxM,'RequestedRangeStepM',NaN, ...
        'ActualRangeStepM',formulaRangeMaxM,'NRange',2, ...
        'RangeStepApplied',false,'OverCoverageM',0, ...
        'RBoxKm',ceil(formulaRangeMaxM/1000)+1);
    return;
end

if ~ismember(pathType,{'source_to_bottom','bottom_to_receiver'})
    error('G3:UnknownBellhopPathType','Unknown BELLHOP path type: %s.',pathType);
end
rangeStepM = positiveScalarLocal(rangeStepM,'rangeStepM');
nIntervals = ceil(formulaRangeMaxM/rangeStepM);
envRangeMaxM = nIntervals*rangeStepM;
actualStepM = envRangeMaxM/nIntervals;
overCoverageM = envRangeMaxM-formulaRangeMaxM;
tol = 64*eps(max([1,formulaRangeMaxM,envRangeMaxM,rangeStepM]));
if envRangeMaxM+tol < formulaRangeMaxM || overCoverageM >= rangeStepM+tol
    error('G3:InvalidBellhopCoverage','Range alignment failed coverage contract.');
end
Spec = struct('PathType',pathType,'FormulaRangeMaxM',formulaRangeMaxM, ...
    'EnvRangeMaxM',envRangeMaxM,'RequestedRangeStepM',rangeStepM, ...
    'ActualRangeStepM',actualStepM,'NRange',nIntervals+1, ...
    'RangeStepApplied',true,'OverCoverageM',overCoverageM, ...
    'RBoxKm',ceil(envRangeMaxM/1000)+1);
end

function value = positiveScalarLocal(value,name)
value = double(value);
if ~isscalar(value) || ~isreal(value) || ~isfinite(value) || value <= 0
    error('G3:InvalidPositiveScalar','%s must be a finite positive scalar.',name);
end
end
