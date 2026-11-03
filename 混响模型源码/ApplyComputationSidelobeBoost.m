function [BeamOut, Audit] = ApplyComputationSidelobeBoost(BeamIn, boostDB)
%APPLYCOMPUTATIONSIDELOBEBOOST Build a computation-only beam copy.
% Only V2 residual sidelobes (or an enabled manual residual override) are
% raised.  Main core, skirt, secondary lobes, support ranges and display
% values are not changed.  The engineering rule is
% computeDB = min(0, displayDB + boostDB).

if nargin < 2 || isempty(boostDB)
    boostDB = 5;
end
validateattributes(boostDB,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'},mfilename,'boostDB');
if ~isstruct(BeamIn) || ~isscalar(BeamIn)
    error('ApplyComputationSidelobeBoost:InvalidBeam', ...
        'BeamIn must be a scalar structure.');
end

BeamOut = BeamIn;
Audit = struct('Enabled',true,'BoostDB',double(boostDB), ...
    'AlreadyApplied',false,'WeightModelVersion',NaN, ...
    'AutomaticResidualTouched',false,'ManualResidualTouched',false, ...
    'Changes',struct('Path',{},'OldDB',{},'NewDB',{}, ...
    'OldAmplitude',{},'NewAmplitude',{}));

if isfield(BeamOut,'ComputationSidelobeBoostApplied') && ...
        ~isempty(BeamOut.ComputationSidelobeBoostApplied) && ...
        logical(BeamOut.ComputationSidelobeBoostApplied)
    oldBoost = NaN;
    if isfield(BeamOut,'ComputationSidelobeBoost_dB') && ...
            ~isempty(BeamOut.ComputationSidelobeBoost_dB)
        oldBoost = double(BeamOut.ComputationSidelobeBoost_dB);
    end
    Audit.AlreadyApplied = true;
    if isfinite(oldBoost) && abs(oldBoost-double(boostDB)) <= 1e-12
        Audit.NumChangedEntries = 0;
        return;
    end
    error('ApplyComputationSidelobeBoost:AlreadyApplied', ...
        ['Input Beam already has a %.6g dB computation boost. ' ...
         'Create a fresh compute copy from the display Beam.'],oldBoost);
end

isV2 = false;
if isfield(BeamOut,'WeightModelVersion') && ...
        isnumeric(BeamOut.WeightModelVersion) && ...
        isscalar(BeamOut.WeightModelVersion) && ...
        isfinite(BeamOut.WeightModelVersion)
    Audit.WeightModelVersion = double(BeamOut.WeightModelVersion);
    isV2 = Audit.WeightModelVersion >= 2;
end

if isV2
    modelFields = {'ElevationWeightModel','AzimuthWeightModel'};
    for k = 1:numel(modelFields)
        fn = modelFields{k};
        if ~isfield(BeamOut,fn) || ~isstruct(BeamOut.(fn)) || ...
                ~isscalar(BeamOut.(fn))
            continue;
        end
        [BeamOut.(fn),changes] = boostModelLocal( ...
            BeamOut.(fn),boostDB,[fn '.ResidualSide']);
        if ~isempty(changes)
            Audit.Changes = [Audit.Changes changes]; %#ok<AGROW>
            Audit.AutomaticResidualTouched = true;
        end
    end
end

manualOverride = ~isV2;
if isfield(BeamOut,'ResidualOverrideEnabled') && ...
        ~isempty(BeamOut.ResidualOverrideEnabled)
    manualOverride = manualOverride || logical(BeamOut.ResidualOverrideEnabled);
end
if manualOverride
    manualFields = {'SideDown_dB','ElevSideDown_dB','AzimuthSideDown_dB'};
    for k = 1:numel(manualFields)
        fn = manualFields{k};
        if ~isfield(BeamOut,fn) || isempty(BeamOut.(fn))
            continue;
        end
        oldDB = double(BeamOut.(fn));
        if ~isreal(oldDB) || any(~isfinite(oldDB(:))) || any(oldDB(:)>0)
            error('ApplyComputationSidelobeBoost:InvalidSideDown', ...
                '%s must contain finite real values <= 0 dB.',fn);
        end
        newDB = min(0,oldDB+double(boostDB));
        BeamOut.(fn) = reshape(newDB,size(BeamOut.(fn)));
        Audit.Changes(end+1) = makeChangeLocal(fn,oldDB,newDB); %#ok<AGROW>
        Audit.ManualResidualTouched = true;
    end
end

BeamOut.ComputationSidelobeBoostApplied = true;
BeamOut.ComputationSidelobeBoost_dB = double(boostDB);
Audit.NumChangedEntries = numel(Audit.Changes);
end

function [model,changes] = boostModelLocal(model,boostDB,basePath)
changes = struct('Path',{},'OldDB',{},'NewDB',{}, ...
    'OldAmplitude',{},'NewAmplitude',{});
if ~isfield(model,'ResidualSide') || ~isstruct(model.ResidualSide) || ...
        ~isscalar(model.ResidualSide)
    return;
end
R = model.ResidualSide;
sideNames = {'NegativeSide','PositiveSide'};
for k = 1:numel(sideNames)
    fn = sideNames{k};
    if ~isfield(R,fn) || ~isstruct(R.(fn)) || ~isscalar(R.(fn))
        continue;
    end
    side = R.(fn);
    if isfield(side,'Enabled') && ~isempty(side.Enabled) && ...
            ~logical(side.Enabled)
        continue;
    end
    [oldDB,ok] = readLevelDBLocal(side);
    if ~ok
        continue;
    end
    if oldDB > 0
        error('ApplyComputationSidelobeBoost:InvalidResidualLevel', ...
            '%s.%s residual level must be <= 0 dB.',basePath,fn);
    end
    newDB = min(0,oldDB+double(boostDB));
    side.Level_dB = newDB;
    side.LevelAmplitude = 10^(newDB/20);
    if isfield(side,'EquivalentWidthDeg') && ...
            isnumeric(side.EquivalentWidthDeg) && ...
            isscalar(side.EquivalentWidthDeg) && ...
            isfinite(side.EquivalentWidthDeg) && side.EquivalentWidthDeg >= 0
        side.EquivalentEnergy = side.LevelAmplitude^2 * ...
            double(side.EquivalentWidthDeg);
    end
    R.(fn) = side;
    changes(end+1) = makeChangeLocal( ...
        sprintf('%s.%s',basePath,fn),oldDB,newDB); %#ok<AGROW>
end
% Synchronize only aliases that already exist; do not create a new range.
if isfield(R,'NegativeSide')
    if isfield(R,'Lower'), R.Lower=R.NegativeSide; end
    if isfield(R,'Left'), R.Left=R.NegativeSide; end
end
if isfield(R,'PositiveSide')
    if isfield(R,'Upper'), R.Upper=R.PositiveSide; end
    if isfield(R,'Right'), R.Right=R.PositiveSide; end
end
model.ResidualSide = R;
end

function [levelDB,ok] = readLevelDBLocal(side)
levelDB = NaN; ok = false;
if isfield(side,'Level_dB') && ~isempty(side.Level_dB)
    levelDB = double(side.Level_dB);
    ok = isscalar(levelDB) && isreal(levelDB) && ...
        (isfinite(levelDB) || isinf(levelDB) && levelDB < 0);
elseif isfield(side,'LevelAmplitude') && ~isempty(side.LevelAmplitude)
    amp = double(side.LevelAmplitude);
    if ~isscalar(amp) || ~isreal(amp) || ~isfinite(amp) || amp < 0
        error('ApplyComputationSidelobeBoost:InvalidResidualAmplitude', ...
            'Residual LevelAmplitude must be a finite nonnegative scalar.');
    end
    if amp == 0, levelDB=-Inf; else, levelDB=20*log10(amp); end
    ok = true;
end
if ~ok
    error('ApplyComputationSidelobeBoost:InvalidResidualDB', ...
        'Residual Level_dB must be a finite scalar or negative infinity.');
end
end

function c = makeChangeLocal(path,oldDB,newDB)
c = struct('Path',path,'OldDB',oldDB,'NewDB',newDB, ...
    'OldAmplitude',10.^(oldDB/20),'NewAmplitude',10.^(newDB/20));
end

