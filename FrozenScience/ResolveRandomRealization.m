function [InputParams, Info] = ResolveRandomRealization(InputParams)
%ResolveRandomRealization Resolve one run-wide automatic or specified seed.
%   Automatic mode generates exactly one seedUsed and records it in the
%   returned InputParams. Reusing that returned seed exactly replays the run.

if nargin < 1 || ~isstruct(InputParams)
    error('ResolveRandomRealization:InvalidInput', 'InputParams must be a struct.');
end
if ~isfield(InputParams, 'ScatterGrid') || ~isstruct(InputParams.ScatterGrid)
    InputParams.ScatterGrid = struct();
end
grid = InputParams.ScatterGrid;

if ~isfield(grid, 'RandomModel') || isempty(grid.RandomModel)
    grid.RandomModel = 'event_white_phase';
end
if ~strcmpi(string(grid.RandomModel), "event_white_phase")
    error('ResolveRandomRealization:UnsupportedRandomModel', ...
        'This remediation supports RandomModel="event_white_phase" only.');
end
grid.RandomModel = 'event_white_phase';

if ~isfield(grid, 'RandomModelVersion') || isempty(grid.RandomModelVersion)
    grid.RandomModelVersion = 1;
end
validateattributes(grid.RandomModelVersion, {'numeric'}, ...
    {'scalar','real','finite','integer','positive'}, mfilename, 'RandomModelVersion');
grid.RandomModelVersion = double(grid.RandomModelVersion);

if isfield(grid, 'RandomSeed')
    requested = grid.RandomSeed;
else
    requested = [];
end

if ~isempty(requested)
    % An explicit requested seed always wins over stale automatic metadata;
    % this is the supported replay path for a recorded automatic run.
    seedUsed = validateSeedLocal(requested);
    mode = 'specified';
else
    alreadyResolvedAutomatic = isfield(grid, 'RandomSeedUsed') && ...
        ~isempty(grid.RandomSeedUsed) && isfield(grid, 'RandomSeedMode') && ...
        strcmpi(string(grid.RandomSeedMode), "automatic");
    if alreadyResolvedAutomatic
        seedUsed = validateSeedLocal(grid.RandomSeedUsed);
        mode = 'automatic';
    else
        seedUsed = automaticSeedLocal();
        mode = 'automatic';
    end
end

grid.RandomSeed = requested;
grid.RandomSeedUsed = seedUsed;
grid.RandomSeedMode = string(mode);
InputParams.ScatterGrid = grid;

Info = struct();
Info.RandomSeedRequested = requested;
Info.RandomSeedUsed = seedUsed;
Info.RandomSeedMode = string(mode);
Info.RandomModel = grid.RandomModel;
Info.RandomModelVersion = grid.RandomModelVersion;
if isfield(grid, 'RealizationIndex')
    Info.RealizationIndex = grid.RealizationIndex;
elseif isfield(InputParams, 'RealizationIndex')
    Info.RealizationIndex = InputParams.RealizationIndex;
else
    Info.RealizationIndex = [];
end
end

function seed = validateSeedLocal(value)
validateattributes(value, {'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative','<=',double(intmax('uint32'))}, ...
    mfilename, 'RandomSeed');
seed = double(value);
end

function seed = automaticSeedLocal()
% UUID supplies per-run entropy without assigning RNG state to workers.
try
    token = char(java.util.UUID.randomUUID());
    [~, numericId] = StableKeyHash('automatic-seed', token);
    seed = mod(numericId, double(intmax('uint32')) + 1);
catch
    rng('shuffle');
    seed = floor(rand() * (double(intmax('uint32')) + 1));
end
seed = double(seed);
end
