function [randomBase, eventKey, eventKeyId] = ScatterEventRandomUnit( ...
        seedUsed, interfaceType, cellKey, pathInstanceKey, randomModelVersion)
%ScatterEventRandomUnit Deterministic event-level M2 random phase basis.
%   Same seed + same keys + same version gives the same value independently
%   of traversal order, parfor scheduling, and worker count.

if nargin < 5 || isempty(randomModelVersion)
    randomModelVersion = 1;
end
validateattributes(seedUsed, {'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'}, mfilename, 'seedUsed');

interfaceType = lower(strtrim(char(string(interfaceType))));
cellKey = char(string(cellKey));
pathInstanceKey = char(string(pathInstanceKey));
eventKey = sprintf('%s|%s|%s', interfaceType, cellKey, pathInstanceKey);
[randomBase, eventKeyId] = StableKeyHash( ...
    'event_white_phase', double(randomModelVersion), double(seedUsed), eventKey);
end

