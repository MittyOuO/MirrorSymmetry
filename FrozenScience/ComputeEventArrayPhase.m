function [DeltaR, DeltaTau, Meta] = ComputeEventArrayPhase(EventXYZ, ElementXYZ, CenterXYZ, cLocal)
% ComputeEventArrayPhase  Range and delay offsets from array center to elements.
%
% EventXYZ   : nEvent-by-3 [x y z] positions.
% ElementXYZ : nElement-by-3 [x y z] element positions.
% CenterXYZ  : 1-by-3 reference receiver position.
% cLocal     : local receive sound speed.

    if nargin < 4 || isempty(cLocal) || ~isfinite(cLocal) || cLocal <= 0
        cLocal = 1500;
    end
    if nargin < 3 || isempty(CenterXYZ)
        error('ComputeEventArrayPhase:MissingCenterXYZ', 'CenterXYZ is required.');
    end
    if nargin < 2 || isempty(ElementXYZ)
        error('ComputeEventArrayPhase:MissingElementXYZ', 'ElementXYZ is required.');
    end
    if nargin < 1 || isempty(EventXYZ)
        DeltaR = zeros(size(ElementXYZ, 1), 0);
        DeltaTau = DeltaR;
        Meta = struct('NumEvents', 0, 'NumElements', size(ElementXYZ, 1));
        return;
    end

    EventXYZ = double(EventXYZ);
    ElementXYZ = double(ElementXYZ);
    CenterXYZ = double(CenterXYZ(:).');
    if size(EventXYZ, 2) ~= 3 && size(EventXYZ, 1) == 3
        EventXYZ = EventXYZ.';
    end
    if size(ElementXYZ, 2) ~= 3 && size(ElementXYZ, 1) == 3
        ElementXYZ = ElementXYZ.';
    end
    if size(EventXYZ, 2) ~= 3 || size(ElementXYZ, 2) ~= 3 || numel(CenterXYZ) ~= 3
        error('ComputeEventArrayPhase:InvalidSize', 'Inputs must be N-by-3 coordinates.');
    end

    nElem = size(ElementXYZ, 1);
    nEv = size(EventXYZ, 1);
    rCenter = sqrt(sum(bsxfun(@minus, EventXYZ, CenterXYZ).^2, 2)).';
    % Vectorized pairwise ranges.  This replaces the former 512-element
    % MATLAB loop with one small matrix product per event chunk.
    elemNorm2 = sum(ElementXYZ.^2,2);
    eventNorm2 = sum(EventXYZ.^2,2).';
    range2 = bsxfun(@plus,elemNorm2,eventNorm2) - 2*(ElementXYZ*EventXYZ.');
    range2 = max(range2,0); % suppress round-off below zero
    rElem = sqrt(range2);
    DeltaR = bsxfun(@minus,rElem,rCenter);
    DeltaTau = DeltaR ./ double(cLocal);

    Meta = struct();
    Meta.NumEvents = nEv;
    Meta.NumElements = nElem;
    Meta.MinDeltaR = min(DeltaR(:));
    Meta.MaxDeltaR = max(DeltaR(:));
    Meta.MinDeltaTau = min(DeltaTau(:));
    Meta.MaxDeltaTau = max(DeltaTau(:));
end
