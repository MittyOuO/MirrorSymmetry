function pathKey = BuildScatterPathInstanceKey(nIn, nOut, counts, delayIn, delayOut)
%BuildScatterPathInstanceKey Stable arrival-pair identifier within a cell.
%   Arrival indices remove collisions between paths that share bounce counts.
%   Quantized delays are diagnostic tie-breakers and remain deterministic.

if nargin < 3 || isempty(counts)
    counts = [NaN NaN NaN NaN];
end
counts = double(counts(:).');
counts(end + 1:4) = NaN;
if nargin < 4 || isempty(delayIn), delayIn = NaN; end
if nargin < 5 || isempty(delayOut), delayOut = NaN; end

pathKey = sprintf(['nIn=%d|nOut=%d|Bi=%g|Ti=%g|Bo=%g|To=%g|', ...
    'delayInNs=%.0f|delayOutNs=%.0f'], ...
    round(double(nIn)), round(double(nOut)), counts(1), counts(2), ...
    counts(3), counts(4), round(double(delayIn) * 1e9), ...
    round(double(delayOut) * 1e9));
end

