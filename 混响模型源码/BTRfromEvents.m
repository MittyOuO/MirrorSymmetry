function [BTR, timeAxis, scanAngles, BTRInfo, BTRLinear] = BTRfromEvents(EventTable, ArrayGeom, TxSignalForSim, Fs, BTRParams)
% BTRfromEvents  Event-level beam-time response (BTR) synthesis.
%
%   [BTR, timeAxis, scanAngles, BTRInfo] = BTRfromEvents( ...
%       EventTable, ArrayGeom, TxSignalForSim, Fs, BTRParams)
%
% The receiving array is always an HLA. scanAngles are its horizontal
% beam angles in [-90, 90] deg, with direction cosine
%
%       scanU = sind(scanAngles)
%
% PhaseMode='full_3D_HLA' uses the real ElementXYZ and event X/Y/Z to
% compute element range, phase and optional element-delay differences.
% SteeringMode='nominal_horizontal' still scans as the nominal horizontal
% HLA: 0 deg is broadside and +/-90 deg is endfire.
%
%       r_m     = sqrt((X - X_rx - x_m)^2 + Y^2)
%       r_center= sqrt((X - X_rx)^2       + Y^2)
%       dR_m    = r_m - r_center
%
% Then each event is projected onto the scanning beams by
%
%       AF(theta,event) = (1/N) * sum_m exp(-j k x_m sin(theta)) ...
%                                      * exp(-j k dR_m)
%
% Notes:
%   1. horizontal_projection remains available for compatibility.
%   2. If required event coordinates are missing, the function falls back to the corrected far-field
%      direction-cosine response using eventU = cosd(PhiR).
%   3. Direct events are excluded by default.
%
% Inputs
%   EventTable      : struct array or table. Required fields are Delay and
%                     ComplexGain. PhiR is optional if X/Y/RecvRange exist.
%                     Optional fields: X, Y, Z, ScatterType, PathClass.
%   ArrayGeom       : receive array geometry. Horizontal line array along x.
%                     Common fields:
%                       N / NumElements / NArray
%                       d / ArraySpacing / ElementSpacing
%                       ElementX
%                       RecvRange / ReferenceRange / CenterRange
%                       Rd / ReceiverDepth
%                       c / SoundSpeed
%   TxSignalForSim  : transmit waveform used for convolution.
%   Fs              : original sampling rate of TxSignalForSim.
%   BTRParams       : optional parameters:
%                       ScanAngles       default -90:2:90 deg
%                       TWindow          default 50 s
%                       BTRFs            default min(Fs, 200) Hz
%                       TimeStep         if given, BTRFs = 1/TimeStep
%                       fBeam            steering frequency
%                       c                sound speed fallback, default 1500
%                       SSP              N x 2 [depth, c] for c(Rd)
%                       SmoothTime       default 0.05 s
%                       IncludeDirect    default false
%                       NormalizeDB      default true
%                       ChunkSize        default 2000 events
%                       PathClassFilter  char/string/cell, optional
%                       PhaseMode        horizontal_projection/full_3D_HLA
%                       SteeringMode     nominal_horizontal/geometry_matched
%                       ApplyElementDelay default true in full_3D_HLA mode
%
% Outputs
%   BTR        : scanAngle x time matrix in dB by default.
%   timeAxis   : time axis in seconds.
%   scanAngles : scan angle vector in degrees.
%   BTRInfo    : diagnostic information.

if nargin < 5 || isempty(BTRParams)
    BTRParams = struct();
end
BTRLinear = struct('yBTR',[]);
cancelFlagFile = getFieldOrDefaultLocal(BTRParams,'CancelFlagFile','');
statusFcn = getFieldOrDefaultLocal(BTRParams,'StatusFcn',[]);
checkBTRCancelLocal(cancelFlagFile);
if nargin < 4 || isempty(Fs)
    error('BTRfromEvents:MissingFs', 'Fs 不能为空。');
end
if nargin < 3
    TxSignalForSim = [];
end
if nargin < 2 || isempty(ArrayGeom)
    ArrayGeom = struct();
end

% 2026-09-16 verified wideband authority.  The legacy narrowband body is
% retained below only for source-history comparison and is unreachable from
% the production entry point.
[BTR,timeAxis,scanAngles,BTRInfo,BTRLinear] = runWidebandAuthorityLocal( ...
    EventTable,ArrayGeom,TxSignalForSim,Fs,BTRParams);
return;

% -------------------------------------------------------------------------
% 1. Parameters and geometry
% -------------------------------------------------------------------------
scanAngles = getFieldOrDefaultLocal(BTRParams, 'ScanAngles', -90:2:90);
scanAngles = double(scanAngles(:));
nScan = numel(scanAngles);

TWindow = getFieldOrDefaultLocal(BTRParams, 'TWindow', 50);
if isfield(BTRParams, 'TimeStep') && ~isempty(BTRParams.TimeStep)
    BTRFs = 1 / double(BTRParams.TimeStep);
else
    BTRFs = getFieldOrDefaultLocal(BTRParams, 'BTRFs', min(double(Fs), 200));
end
BTRFs = double(BTRFs);
if BTRFs <= 0
    error('BTRfromEvents:InvalidBTRFs', 'BTRFs 必须为正数。');
end

smoothTime = getFieldOrDefaultLocal(BTRParams, 'SmoothTime', 0.05);
includeDirect = logical(getFieldOrDefaultLocal(BTRParams, 'IncludeDirect', false));
normalizeDB = logical(getFieldOrDefaultLocal(BTRParams, 'NormalizeDB', true));
chunkSize = getFieldOrDefaultLocal(BTRParams, 'ChunkSize', 2000);
chunkSize = max(1, round(double(chunkSize)));
phaseMode = parsePhaseModeLocal(getFieldOrDefaultLocal(BTRParams, 'PhaseMode', 'horizontal_projection'));
useFull3DHLA = strcmpi(phaseMode, 'full_3D_HLA');
steeringMode = parseSteeringModeLocal(getFieldOrDefaultLocal(BTRParams, 'SteeringMode', 'nominal_horizontal'));
applyElementDelay = logical(getFieldOrDefaultLocal(BTRParams, 'ApplyElementDelay', useFull3DHLA));

ArrayGeom = normalizeArrayGeomLocal(ArrayGeom, BTRParams);
N = ArrayGeom.N;
xElem = double(ArrayGeom.ElementX(:));
elementXYZ = double(ArrayGeom.ElementXYZ);
nominalElementXYZ = double(ArrayGeom.NominalElementXYZ);
centerXYZ = double(ArrayGeom.CenterXYZ(:).');

cLocal = getLocalSoundSpeedLocal(ArrayGeom, BTRParams);
fBeam = getFieldOrDefaultLocal(BTRParams, 'fBeam', []);
if isempty(fBeam)
    fBeam = estimateDominantFreqLocal(TxSignalForSim, Fs);
end
if isempty(fBeam) || ~isfinite(fBeam) || fBeam <= 0
    fBeam = 500;
end
k = 2 * pi * fBeam / cLocal;

nTime = ceil(TWindow * BTRFs) + 1;
timeAxis = (0:nTime-1) / BTRFs;

% The scan angle is a horizontal line-array beam angle. Its spatial
% frequency along the array is u = sin(theta).
scanU = sind(scanAngles(:)).';                 % 1 x nScan
if exist('BuildHLASteeringVector', 'file') == 2
    [steerPhase, steeringInfo] = BuildHLASteeringVector(ArrayGeom, scanAngles, k, steeringMode);
else
    steerPhase = exp(-1i * k * (xElem * scanU));   % N x nScan
    steeringInfo = struct('SteeringMode', steeringMode, 'GeometrySource', 'ElementX_fallback');
end

% -------------------------------------------------------------------------
% 2. Extract and filter event fields
% -------------------------------------------------------------------------
notifyBTRStatusLocal(statusFcn,'BTR 事件整理进度：0%。');
E = extractEventsLocal(EventTable, ArrayGeom, statusFcn, cancelFlagFile);
numInputEvents = numel(E.Delay);
if numInputEvents == 0
    BTR = zeros(nScan, nTime);
    BTRLinear.yBTR = complex(zeros(nScan,nTime));
    BTRInfo = makeInfoLocal(numInputEvents, 0, 0, 0, ArrayGeom, BTRParams, BTRFs, fBeam, cLocal, 'empty EventTable');
    return;
end

notifyBTRStatusLocal(statusFcn,'BTR 事件筛选进度：0%。');
valid = isfinite(E.Delay) & E.Delay >= 0 & E.Delay <= TWindow & ...
        isfinite(real(E.ComplexGain)) & isfinite(imag(E.ComplexGain));

% PhiR is only required for the far-field fallback. Keep invalid PhiR if X/Y
% are available for near-field computation.
hasXYAll = isfinite(E.X) & isfinite(E.Y);
valid = valid & (hasXYAll | isfinite(E.PhiR));

isDirect = false(size(valid));
if ~includeDirect && ~isempty(E.ScatterType)
    isDirect = strcmpi(strtrim(E.ScatterType), 'direct');
end

useMask = valid & ~isDirect;
numDirectExcluded = sum(valid & isDirect);

E = applyEventMaskLocal(E, useMask);

% Optional PathClass filtering.
pathClassFilter = getFieldOrDefaultLocal(BTRParams, 'PathClassFilter', []);
numPathClassExcluded = 0;
if ~isempty(pathClassFilter) && ~isAllFilterLocal(pathClassFilter)
    if ~isfield(E, 'PathClass') || isempty(E.PathClass) || all(cellfun(@isempty, E.PathClass))
        warning('BTRfromEvents:MissingPathClass', ...
            '已设置 BTRParams.PathClassFilter，但事件表中没有 PathClass 字段。筛选结果为空。');
        pathMask = false(size(E.Delay));
    else
        pathMask = makePathClassMaskLocal(E.PathClass, pathClassFilter);
    end
    numPathClassExcluded = sum(~pathMask);
    E = applyEventMaskLocal(E, pathMask);
end
checkBTRCancelLocal(cancelFlagFile);
notifyBTRStatusLocal(statusFcn,'BTR 事件筛选进度：100%。');

numUsedEvents = numel(E.Delay);
if numUsedEvents == 0
    BTR = zeros(nScan, nTime);
    BTRLinear.yBTR = complex(zeros(nScan,nTime));
    BTRInfo = makeInfoLocal(numInputEvents, 0, numDirectExcluded, numPathClassExcluded, ...
        ArrayGeom, BTRParams, BTRFs, fBeam, cLocal, 'no valid events after filtering');
    BTRInfo.PathClassFilter = pathClassFilter;
    return;
end

% -------------------------------------------------------------------------
% 3. Event-level near-field beamforming impulse response
% -------------------------------------------------------------------------
hBTR = complex(zeros(nScan, nTime));
if useFull3DHLA && applyElementDelay
    % First accumulate event contributions on the element-time plane.  The
    % steering weight depends only on element and scan angle, so applying
    % all scan weights inside every event chunk repeats the same work
    % nScan times.  Sparse accumulation followed by one matrix beamforming
    % pass is algebraically identical and is much faster for large event
    % tables and 512-element arrays.
    hElementDelay = sparse(N, nTime);
else
    hElementDelay = [];
end

recvRange = ArrayGeom.RecvRange;
numNearFieldEvents = 0;
numFarFieldFallbackEvents = 0;
numFull3DEvents = 0;
numHorizontalProjectionEvents = 0;
numMissing3DGeometryFallbackEvents = 0;
notifyBTRStatusLocal(statusFcn,sprintf( ...
    ['BTR 合成准备：%d 个事件，%d 个接收阵元，%d 个扫描角，', ...
    '%d 个时间采样点；PhaseMode=%s，ApplyElementDelay=%d。'], ...
    numUsedEvents,N,nScan,nTime,phaseMode,applyElementDelay));
notifyBTRStatusLocal(statusFcn,'BTR 事件—阵元时延累加进度：0%。');
eventProgressPct = 0;

for i0 = 1:chunkSize:numUsedEvents
    checkBTRCancelLocal(cancelFlagFile);
    i1 = min(i0 + chunkSize - 1, numUsedEvents);
    idxEvent = i0:i1;

    delayChunk = E.Delay(idxEvent);
    gainChunk = E.ComplexGain(idxEvent);
    xChunk = E.X(idxEvent);
    yChunk = E.Y(idxEvent);
    zChunk = E.Z(idxEvent);
    phiChunk = E.PhiR(idxEvent);

    tIdx = round(delayChunk * BTRFs) + 1;
    inside = tIdx >= 1 & tIdx <= nTime;
    if ~any(inside)
        eventProgressPct = reportBTRProgressLocal( ...
            'BTR 事件—阵元时延累加',i1,numUsedEvents,eventProgressPct,statusFcn);
        continue;
    end

    tIdx = tIdx(inside);
    delayChunk = delayChunk(inside);
    gainChunk = gainChunk(inside);
    xChunk = xChunk(inside);
    yChunk = yChunk(inside);
    zChunk = zChunk(inside);
    phiChunk = phiChunk(inside);

    nEv = numel(tIdx);
    AF = complex(zeros(nScan, nEv));
    handledByElementDelay = false(1, nEv);

    nearMask = isfinite(xChunk) & isfinite(yChunk) & isfinite(recvRange);
    if useFull3DHLA
        nearMask = nearMask & isfinite(zChunk) & isfinite(ArrayGeom.Rd);
        missing3D = isfinite(xChunk) & isfinite(yChunk) & isfinite(recvRange) & ...
            (~isfinite(zChunk) | ~isfinite(ArrayGeom.Rd));
        numMissing3DGeometryFallbackEvents = numMissing3DGeometryFallbackEvents + sum(missing3D);
    end
    if any(nearMask)
        if useFull3DHLA
            eventXYZ = [double(xChunk(nearMask)), double(yChunk(nearMask)), double(zChunk(nearMask))];
            [deltaR, deltaTau] = ComputeEventArrayPhase(eventXYZ, elementXYZ, centerXYZ, cLocal);
            numFull3DEvents = numFull3DEvents + sum(nearMask);
        else
            xRel = reshape(double(xChunk(nearMask)) - double(recvRange), 1, []);
            yRel = reshape(double(yChunk(nearMask)), 1, []);
            nominalX = nominalElementXYZ(:, 1) - centerXYZ(1);
            dxElem = bsxfun(@minus, xRel, nominalX);
            yMat = repmat(yRel, N, 1);
            rElem = sqrt(dxElem.^2 + yMat.^2);
            rCenter = reshape(sqrt(xRel.^2 + yRel.^2), 1, []);
            deltaR = bsxfun(@minus, rElem, rCenter);
            deltaTau = deltaR ./ cLocal;
            numHorizontalProjectionEvents = numHorizontalProjectionEvents + sum(nearMask);
        end
        eventPhase = exp(-1i * k * deltaR);       % N x nNear

        if useFull3DHLA && applyElementDelay
            nearIndices = find(nearMask);
            delayNear = reshape(double(delayChunk(nearMask)), 1, []);
            gainNear = reshape(gainChunk(nearMask), 1, []);
            tElem = round(bsxfun(@plus, delayNear, deltaTau) * BTRFs) + 1;
            goodElem = tElem >= 1 & tElem <= nTime;
            elemAmp = bsxfun(@times, eventPhase, gainNear);
            [elemIndex, ~] = find(goodElem);
            timeIndex = tElem(goodElem);
            ampValue = elemAmp(goodElem);

            if ~isempty(timeIndex)
                hElementDelay = hElementDelay + sparse( ...
                    elemIndex(:),timeIndex(:),ampValue(:),N,nTime);
            end
            handledByElementDelay(nearIndices) = true;
        else
            AF(:, nearMask) = (steerPhase.' * eventPhase) / N;
        end
        numNearFieldEvents = numNearFieldEvents + sum(nearMask);
    end

    farMask = ~nearMask & ~handledByElementDelay;
    if any(farMask)
        % Corrected far-field fallback. PhiR is measured from +x, while the
        % displayed beam angle uses u = sin(theta), so eventU = cos(PhiR).
        phiFar = reshape(double(phiChunk(farMask)), 1, []);
        offsetXYZ = bsxfun(@minus, elementXYZ, centerXYZ);
        eventDir = [cosd(phiFar); sind(phiFar); zeros(1, numel(phiFar))];
        eventPhase = exp(1i * k * (offsetXYZ * eventDir)); % N x nFar
        AF(:, farMask) = (steerPhase.' * eventPhase) / N;
        numFarFieldFallbackEvents = numFarFieldFallbackEvents + sum(farMask);
    end

    % Events already accumulated on the element-time plane must not pass
    % through the generic scan-event accumulator again.  Besides avoiding
    % double counting, this removes a large all-zero nScan-by-nEvent
    % allocation in the common full-3D path.
    genericMask = ~handledByElementDelay;
    if any(genericMask)
        genericTime = tIdx(genericMask);
        contrib = AF(:,genericMask) .* reshape(gainChunk(genericMask),1,[]);
        nGeneric = numel(genericTime);
        linIdx = sub2ind([nScan, nTime], ...
            repmat((1:nScan).',1,nGeneric), ...
            repmat(reshape(genericTime,1,[]),nScan,1));
        addVec = accumarray(linIdx(:),contrib(:), ...
            [nScan * nTime,1],@sum,complex(0));
        hBTR = hBTR + reshape(addVec,nScan,nTime);
    end
    eventProgressPct = reportBTRProgressLocal( ...
        'BTR 事件—阵元时延累加',i1,numUsedEvents,eventProgressPct,statusFcn);
end

if ~isempty(hElementDelay) && nnz(hElementDelay) > 0
    checkBTRCancelLocal(cancelFlagFile);
    notifyBTRStatusLocal(statusFcn,sprintf( ...
        'BTR 阵元—时间累加完成：%d 个非零单元；正在进行矩阵成束...', ...
        nnz(hElementDelay)));
    % Work in time blocks so the dense matrix-product temporary remains
    % bounded even when TWindow*BTRFs is large.
    timeBlockSize = max(1000,min(nTime,5000));
    notifyBTRStatusLocal(statusFcn,'BTR 矩阵成束进度：0%。');
    beamProgressPct = 0;
    for j0 = 1:timeBlockSize:nTime
        checkBTRCancelLocal(cancelFlagFile);
        j1 = min(j0 + timeBlockSize - 1,nTime);
        hBTR(:,j0:j1) = hBTR(:,j0:j1) + ...
            (steerPhase.' * hElementDelay(:,j0:j1)) / N;
        beamProgressPct = reportBTRProgressLocal( ...
            'BTR 矩阵成束',j1,nTime,beamProgressPct,statusFcn);
    end
    clear hElementDelay
end

% -------------------------------------------------------------------------
% 4. Convolve beamformed impulse response with transmit signal
% -------------------------------------------------------------------------
txBTR = prepareTxForBTRLocal(TxSignalForSim, Fs, BTRFs);
if isempty(txBTR)
    yBTR = hBTR;
elseif numel(txBTR) == 1
    yBTR = hBTR .* txBTR(1);
else
    yBTR = complex(zeros(size(hBTR)));
    notifyBTRStatusLocal(statusFcn,'BTR 波形卷积进度：0%。');
    convProgressPct = 0;
    useFFTConvolution = numel(txBTR) > 32;
    if useFFTConvolution
        nFFT = 2^nextpow2(nTime + numel(txBTR) - 1);
        txFFT = fft(txBTR,nFFT);
        notifyBTRStatusLocal(statusFcn,sprintf( ...
            'BTR 波形卷积采用 FFT：TxLength=%d，NFFT=%d。',numel(txBTR),nFFT));
    end
    for iscan = 1:nScan
        checkBTRCancelLocal(cancelFlagFile);
        if useFFTConvolution
            yFull = ifft(fft(hBTR(iscan,:),nFFT) .* txFFT);
        else
            yFull = conv(hBTR(iscan,:),txBTR,'full');
        end
        yBTR(iscan, :) = yFull(1:nTime);
        convProgressPct = reportBTRProgressLocal( ...
            'BTR 波形卷积',iscan,nScan,convProgressPct,statusFcn);
    end
end

% -------------------------------------------------------------------------
% 5. Envelope / power display matrix
% -------------------------------------------------------------------------
notifyBTRStatusLocal(statusFcn,'BTR 后处理进度：0%。');
powerBTR = abs(yBTR).^2;
checkBTRCancelLocal(cancelFlagFile);
smoothPts = max(1, round(smoothTime * BTRFs));
if smoothPts > 1
    powerBTR = movmean(powerBTR, smoothPts, 2);
end
notifyBTRStatusLocal(statusFcn,'BTR 后处理进度：50%。');

BTR = 10 * log10(powerBTR + eps);
if normalizeDB
    BTR = BTR - max(BTR(:));
end

BTRInfo = makeInfoLocal(numInputEvents, numUsedEvents, numDirectExcluded, numPathClassExcluded, ...
    ArrayGeom, BTRParams, BTRFs, fBeam, cLocal, 'ok');
BTRInfo.NumScanAngles = nScan;
BTRInfo.NumTimePoints = nTime;
BTRInfo.TxLength_BTR = numel(txBTR);
BTRInfo.OutputUnits = ternaryLocal(normalizeDB, 'dB relative to max', 'dB arbitrary');
BTRInfo.PhaseMode = phaseMode;
BTRInfo.SteeringMode = steeringMode;
BTRInfo.ApplyElementDelay = applyElementDelay;
BTRInfo.GeometryMode = getFieldOrDefaultLocal(ArrayGeom, 'GeometryMode', 'horizontal');
BTRInfo.PitchDeg = getFieldOrDefaultLocal(ArrayGeom, 'PitchDeg', 0);
BTRInfo.ArrayHeadingDeg = getFieldOrDefaultLocal(ArrayGeom, 'ArrayHeadingDeg', 0);
BTRInfo.SteeringInfo = steeringInfo;
BTRInfo.ArrayGeom = ArrayGeom;
if useFull3DHLA
    BTRInfo.BeamformingModel = 'full_3D_HLA_nearfield_spherical_phase';
    BTRInfo.ScanAngleDefinition = 'horizontal HLA scan: 0 deg broadside, +/-90 deg endfire; event phase uses X/Y/Z';
else
    BTRInfo.BeamformingModel = 'horizontal_nearfield_spherical_phase';
    BTRInfo.ScanAngleDefinition = 'scanU = sind(scanAngles); eventU = cosd(PhiR)';
end
BTRInfo.NumNearFieldEvents = numNearFieldEvents;
BTRInfo.NumFarFieldFallbackEvents = numFarFieldFallbackEvents;
BTRInfo.NumFull3DEvents = numFull3DEvents;
BTRInfo.NumHorizontalProjectionEvents = numHorizontalProjectionEvents;
BTRInfo.NumMissing3DGeometryFallbackEvents = numMissing3DGeometryFallbackEvents;
BTRInfo.PathClassFilter = pathClassFilter;
notifyBTRStatusLocal(statusFcn,'BTR 后处理进度：80%。');
if isfield(E, 'PathClass') && ~isempty(E.PathClass)
    BTRInfo.PathClassesUsed = unique(E.PathClass);
else
    BTRInfo.PathClassesUsed = {};
end
BTRInfo.HBTR = []; % intentionally not returned by default to save memory
BTRLinear.yBTR = yBTR;
notifyBTRStatusLocal(statusFcn,'BTR 后处理进度：100%。');

end

% ========================================================================
% Local helper functions
% ========================================================================
function [BTR,timeAxis,scanAngles,BTRInfo,BTRLinear] = runWidebandAuthorityLocal( ...
        EventTable,ArrayGeom,TxSignalForSim,Fs,P)
    P.ScanAngles = getFieldOrDefaultLocal(P,'ScanAngles',-90:2:90);
    P.TWindow = getFieldOrDefaultLocal(P,'TWindow',50);
    P.BTRFs = getFieldOrDefaultLocal(P,'BTRFs',min(Fs,200));
    if isfield(P,'TimeStep') && ~isempty(P.TimeStep)
        P.BTRFs = 1/P.TimeStep;
    end
    P.SmoothTime = getFieldOrDefaultLocal(P,'SmoothTime',0.05);
    P.SteeringMode = parseSteeringModeLocal( ...
        getFieldOrDefaultLocal(P,'SteeringMode','nominal_horizontal'));
    validateattributes(Fs,{'numeric'},{'scalar','positive','finite'});
    validateattributes(P.BTRFs,{'numeric'},{'scalar','positive','finite'});
    validateattributes(P.TWindow,{'numeric'},{'scalar','positive','finite'});
    validateattributes(P.SmoothTime,{'numeric'},{'scalar','nonnegative','finite'});

    statusFcn = getFieldOrDefaultLocal(P,'StatusFcn',[]);
    cancelFlagFile = getFieldOrDefaultLocal(P,'CancelFlagFile','');
    G = normalizeArrayGeomLocal(ArrayGeom,P);
    c = getLocalSoundSpeedLocal(G,P);
    E = extractEventsLocal(EventTable,G,statusFcn,cancelFlagFile);
    nInput = numel(E.Delay);
    receiveMode=lower(char(string(getFieldOrDefaultLocal(P,'ReceivePhaseMode','legacy_geometric'))));
    strictReceive=ismember(receiveMode,{'terminal_k','exact_element_delays'});
    if ~strictReceive && ~strcmp(receiveMode,'legacy_geometric')
        error('ReceivePath:UnsupportedMode','Unsupported ReceivePhaseMode; full Green needs a separate operator.');
    end
    if ~strictReceive && getFieldOrDefaultLocal(P,'RequireQualifiedReceivePath',false)
        error('ReceivePath:LegacyNotQualified','legacy_geometric is not a terminal-path qualification.');
    end
    if strictReceive
        if istable(EventTable),E.ReceivePathRecords=table2struct(EventTable);else,E.ReceivePathRecords=EventTable(:);end
        % Validate globally before disk allocation, preserving identity across chunks.
        if ~isempty(E.ReceivePathRecords) && ~all(isfield(E.ReceivePathRecords,{'EventID','FacetID','TxPathInstanceID','RxPathInstanceID'}))
            error('ReceivePath:PendingIdentity','Strict receive mode requires complete ordered path identity.');
        end
        ids=string({E.ReceivePathRecords.EventID});
        if numel(unique(ids))~=numel(ids),error('ReceivePath:DuplicateIdentity','Duplicate EventID.');end
        orderedKeys=strings(nInput,1);
        for i=1:nInput
            r=E.ReceivePathRecords(i);
            orderedKeys(i)=string(jsonencode({string(r.FacetID),string(r.TxPathInstanceID),string(r.RxPathInstanceID)}));
        end
        if numel(unique(orderedKeys))~=nInput,error('ReceivePath:DuplicateIdentity','Duplicate facet and ordered path pair.');end
        for first=1:1024:nInput
            last=min(nInput,first+1023);
            ComputeReceivePathOffsets(E.ReceivePathRecords(first:last),G,c,receiveMode);
        end
    end
    valid = isfinite(E.Delay) & E.Delay>=0 & E.Delay<=P.TWindow & ...
        isfinite(E.ComplexGain) & ...
        (strictReceive | (isfinite(E.X)&isfinite(E.Y)&isfinite(E.Z)) | isfinite(E.PhiR));
    isDirect = strcmpi(strtrim(E.ScatterType),'direct');
    if getFieldOrDefaultLocal(P,'IncludeDirect',false)
        isDirect(:) = false;
    end
    pathMask = makePathClassMaskLocal(E.PathClass, ...
        getFieldOrDefaultLocal(P,'PathClassFilter',[]));
    E = applyEventMaskLocal(E,valid & ~isDirect & pathMask);
    scanAngles = double(P.ScanAngles(:));

    [diskFile,kernelInfo] = WidebandBTRKernel( ...
        E,G,TxSignalForSim,Fs,scanAngles,P,c);
    BTRInfo = makeInfoLocal(nInput,numel(E.Delay),sum(valid&isDirect), ...
        sum(valid&~pathMask),G,P,P.BTRFs, ...
        getFieldOrDefaultLocal(P,'fBeam',NaN),c,'ok');
    names = fieldnames(kernelInfo);
    for k = 1:numel(names)
        BTRInfo.(names{k}) = kernelInfo.(names{k});
    end
    BTRInfo.PhaseMode = receiveMode;
    BTRInfo.ReceivePathPhysicalQualification = 'NOT_INFERRED_FROM_SYNTHESIS';
    BTRInfo.ApplyElementDelay = true;
    BTRInfo.SteeringMode = P.SteeringMode;
    BTRInfo.ArrayGeom = G;
    BTRInfo.PathClassesUsed = unique(E.PathClass);
    BTRLinear = struct('yBTR',[],'DiskFile',diskFile);

    if getFieldOrDefaultLocal(P,'ReturnOnDisk',false)
        BTR = [];
        timeAxis = (0:ceil(P.TWindow*Fs))/Fs;
        return;
    end

    cleanupObj = onCleanup(@() delete(diskFile)); %#ok<NASGU>
    disk = matfile(diskFile);
    nOut = ceil(P.TWindow*P.BTRFs)+1;
    nInternal = ceil(P.TWindow*Fs)+1;
    allY = [];
    if numel(scanAngles)*nInternal < 5e6
        allY = disk.yBTR;
    end
    timeAxis = (0:nOut-1)/P.BTRFs;
    BTR = zeros(numel(scanAngles),nOut,'single');
    BTRLinear.yBTR = complex(zeros(numel(scanAngles),nOut,'single'));
    [p,q] = rat(P.BTRFs/Fs,1e-10);
    smoothPoints = max(1,round(P.SmoothTime*Fs));
    for a = 1:numel(scanAngles)
        checkBTRCancelLocal(cancelFlagFile);
        if isempty(allY)
            y = disk.yBTR(:,a).';
        else
            y = allY(:,a).';
        end
        power = movmean(abs(y).^2,smoothPoints,2);
        output = max(0,resample(double(power),p,q));
        count = min(nOut,numel(output));
        BTR(a,1:count) = single(10*log10(max( ...
            output(1:count),realmin('double'))));
        voltage = resample(double(y),p,q);
        countVoltage = min(nOut,numel(voltage));
        BTRLinear.yBTR(a,1:countVoltage) = single(voltage(1:countVoltage));
        if mod(a,40)==0 || a==numel(scanAngles)
            notifyBTRStatusLocal(statusFcn,sprintf( ...
                'BTR output rows: %d/%d',a,numel(scanAngles)));
        end
    end
    if getFieldOrDefaultLocal(P,'NormalizeDB',true) && ~isempty(BTR)
        BTR = BTR-max(BTR(:));
    end
    BTRLinear.DiskFile = '';
end

function phaseMode = parsePhaseModeLocal(rawMode)
    phaseMode = lower(strtrim(char(string(rawMode))));
    switch phaseMode
        case {'horizontal_projection','horizontal','legacy','old'}
            phaseMode = 'horizontal_projection';
        case {'full_3d_hla','full3d','full_3d','3d_hla'}
            phaseMode = 'full_3D_HLA';
        otherwise
            error('BTRfromEvents:InvalidPhaseMode', ...
                'BTRParams.PhaseMode must be horizontal_projection or full_3D_HLA.');
    end
end

function steeringMode = parseSteeringModeLocal(rawMode)
    steeringMode = lower(strtrim(char(string(rawMode))));
    switch steeringMode
        case {'nominal_horizontal','nominal','horizontal','legacy'}
            steeringMode = 'nominal_horizontal';
        case {'geometry_matched','matched','actual','rigid_tilt'}
            steeringMode = 'geometry_matched';
        otherwise
            error('BTRfromEvents:InvalidSteeringMode', ...
                'BTRParams.SteeringMode must be nominal_horizontal or geometry_matched.');
    end
end

function checkBTRCancelLocal(flagFile)
try
    drawnow limitrate;
catch
end
if ~isempty(flagFile) && exist(char(string(flagFile)),'file') == 2
    error('Reverb:ModelRunStopped','用户已请求停止运行。');
end
end

function ArrayGeom = normalizeArrayGeomLocal(ArrayGeom, BTRParams)
    if exist('BuildTowedArrayGeometry', 'file') == 2
        try
            [ArrayGeom, validation] = BuildTowedArrayGeometry(BTRParams, ArrayGeom);
            ArrayGeom.GeometryValidation = validation;
            return;
        catch ME
            warning('BTRfromEvents:ArrayGeometryFallback', ...
                'BuildTowedArrayGeometry failed, using horizontal fallback: %s', ME.message);
        end
    end

    N = getFirstFieldLocal(ArrayGeom, {'N','NumElements','NArray','ElementCount'}, []);
    if isempty(N)
        N = getFirstFieldLocal(BTRParams, {'N','NumElements','NArray','ElementCount'}, 512);
    end
    N = max(1, round(double(N)));

    d = getFirstFieldLocal(ArrayGeom, {'d','D','ArraySpacing','ElementSpacing'}, []);
    if isempty(d)
        d = getFirstFieldLocal(BTRParams, {'d','D','ArraySpacing','ElementSpacing'}, 1.5);
    end
    d = double(d);

    if isfield(ArrayGeom, 'ElementX') && ~isempty(ArrayGeom.ElementX)
        xElem = double(ArrayGeom.ElementX(:));
        N = numel(xElem);
        xElem = xElem - mean(xElem);
        if N > 1
            d = median(abs(diff(sort(xElem))));
        end
    else
        centerIndex = getFirstFieldLocal(ArrayGeom, {'CenterIndex','RefElementIndex'}, (N + 1) / 2);
        xElem = ((1:N).' - double(centerIndex)) * d;
    end

    recvRange = getFirstFieldLocal(ArrayGeom, {'RecvRange','ReferenceRange','CenterRange','Range'}, []);
    if isempty(recvRange)
        recvRange = getFirstFieldLocal(BTRParams, {'RecvRange','ReferenceRange','CenterRange','Range'}, []);
    end
    if isempty(recvRange)
        recvRange = NaN;
    end

    Rd = getFirstFieldLocal(ArrayGeom, {'Rd','ReceiverDepth','ReferenceDepth'}, []);
    if isempty(Rd)
        Rd = getFirstFieldLocal(BTRParams, {'Rd','ReceiverDepth','ReferenceDepth'}, []);
    end
    if isempty(Rd)
        Rd = NaN;
    end

    ArrayGeom.N = N;
    ArrayGeom.d = d;
    ArrayGeom.ElementX = xElem;
    ArrayGeom.RecvRange = double(recvRange);
    ArrayGeom.Rd = double(Rd);
    ArrayGeom.CenterXYZ = [double(recvRange), 0, double(Rd)];
    ArrayGeom.ElementXYZ = [double(recvRange) + xElem, zeros(N, 1), double(Rd) + zeros(N, 1)];
    ArrayGeom.NominalElementXYZ = ArrayGeom.ElementXYZ;
    ArrayGeom.GeometryMode = 'horizontal';
    ArrayGeom.PitchDeg = 0;
    ArrayGeom.ArrayHeadingDeg = 0;
    ArrayGeom.ElementXYZSource = 'horizontal_fallback';
end

function cLocal = getLocalSoundSpeedLocal(ArrayGeom, BTRParams)
    cLocal = getFirstFieldLocal(ArrayGeom, {'c','C','SoundSpeed','cLocal'}, []);
    if isempty(cLocal)
        cLocal = getFirstFieldLocal(BTRParams, {'c','C','SoundSpeed','cLocal'}, []);
    end

    SSP = [];
    if isfield(BTRParams, 'SSP') && ~isempty(BTRParams.SSP)
        SSP = BTRParams.SSP;
    elseif isfield(ArrayGeom, 'SSP') && ~isempty(ArrayGeom.SSP)
        SSP = ArrayGeom.SSP;
    end

    Rd = getFirstFieldLocal(ArrayGeom, {'Rd','ReceiverDepth','ReferenceDepth'}, []);
    if isempty(Rd) || ~isfinite(Rd)
        Rd = getFirstFieldLocal(BTRParams, {'Rd','ReceiverDepth','ReferenceDepth'}, []);
    end

    if ~isempty(SSP) && ~isempty(Rd) && isnumeric(SSP) && size(SSP,2) >= 2
        try
            cLocal = interp1(double(SSP(:,1)), double(SSP(:,2)), double(Rd), 'linear', 'extrap');
        catch
        end
    end

    if isempty(cLocal) || ~isfinite(cLocal) || cLocal <= 0
        cLocal = 1500;
    end
end

function E = extractEventsLocal(EventTable, ArrayGeom, statusFcn, cancelFlagFile)
    E = struct( ...
        'Delay', [], ...
        'ComplexGain', [], ...
        'PhiR', [], ...
        'X', [], ...
        'Y', [], ...
        'Z', [], ...
        'ScatterType', {{}}, ...
        'PathClass', {{}}, ...
        'PathClassID', []);

    if isempty(EventTable)
        return;
    end

    recvRange = getFirstFieldLocal(ArrayGeom, {'RecvRange','ReferenceRange','CenterRange','Range'}, NaN);

    if istable(EventTable)
        n = height(EventTable);
        checkBTRCancelLocal(cancelFlagFile);
        E.Delay = getTableFieldLocal(EventTable, {'Delay','delay'});
        E.ComplexGain = getTableFieldLocal(EventTable, {'ComplexGain','Gain','Amp'});
        if isempty(E.ComplexGain)
            p = getTableFieldLocal(EventTable, {'PowerGain','Power'});
            E.ComplexGain = sqrt(max(p, 0));
        end
        E.PhiR = getTableFieldLocal(EventTable, {'PhiR','phiR','Bearing','ArrivalAzimuth','Azimuth'});
        E.X = getTableFieldLocal(EventTable, {'X','x'});
        E.Y = getTableFieldLocal(EventTable, {'Y','y'});
        E.Z = getTableFieldLocal(EventTable, {'Z','z','Depth','ScatterDepth'});

        if isempty(E.Delay), E.Delay = nan(n,1); end
        if isempty(E.ComplexGain), E.ComplexGain = complex(nan(n,1)); end
        if isempty(E.PhiR), E.PhiR = nan(n,1); end
        if isempty(E.X), E.X = nan(n,1); end
        if isempty(E.Y), E.Y = nan(n,1); end
        if isempty(E.Z), E.Z = nan(n,1); end

        badPhi = ~isfinite(E.PhiR) & isfinite(E.X) & isfinite(E.Y) & isfinite(recvRange);
        E.PhiR(badPhi) = atan2d(E.Y(badPhi), E.X(badPhi) - recvRange);

        E.ScatterType = getTableCellstrLocal(EventTable, {'ScatterType','Type'});
        E.PathClass = getTableCellstrLocal(EventTable, {'PathClass','pathClass','PathType'});
        E.PathClassID = getTableFieldLocal(EventTable, {'PathClassID','pathClassID','PathID'});
        if isempty(E.PathClassID), E.PathClassID = nan(n,1); end
        notifyBTRStatusLocal(statusFcn,'BTR 事件整理进度：100%。');
        return;
    end

    if ~isstruct(EventTable)
        error('BTRfromEvents:InvalidEventTable', 'EventTable 必须为 struct array 或 table。');
    end

    n = numel(EventTable);

    % The simulator produces homogeneous scalar struct events.  Extract
    % those fields as comma-separated vectors in one operation.  This
    % avoids millions of scalar getStructScalarLocal calls before the first
    % visible BTR progress update.  Irregular external event structures
    % retain the compatible element-by-element fallback below.
    try
        [delayFast,okDelay] = getStructNumericVectorFastLocal( ...
            EventTable,{'Delay','delay'},n);
        [gainFast,okGain] = getStructNumericVectorFastLocal( ...
            EventTable,{'ComplexGain','Gain','Amp'},n);
        if ~okGain
            [powerFast,okPower] = getStructNumericVectorFastLocal( ...
                EventTable,{'PowerGain','Power'},n);
            if okPower
                gainFast = sqrt(max(powerFast,0));
                okGain = true;
            end
        end
        [phiFast,okPhi] = getStructNumericVectorFastLocal( ...
            EventTable,{'PhiR','phiR','Bearing','ArrivalAzimuth','Azimuth'},n);
        [xFast,okX] = getStructNumericVectorFastLocal(EventTable,{'X','x'},n);
        [yFast,okY] = getStructNumericVectorFastLocal(EventTable,{'Y','y'},n);
        [zFast,okZ] = getStructNumericVectorFastLocal( ...
            EventTable,{'Z','z','Depth','ScatterDepth'},n);
        [scatterFast,okScatter] = getStructTextVectorFastLocal( ...
            EventTable,{'ScatterType','Type'},n);
        [pathFast,okPath] = getStructTextVectorFastLocal( ...
            EventTable,{'PathClass','pathClass','PathType'},n);
        [pathIdFast,okPathId] = getStructNumericVectorFastLocal( ...
            EventTable,{'PathClassID','pathClassID','PathID'},n);

        if okDelay && okGain
            E.Delay = delayFast;
            E.ComplexGain = gainFast;
            if okPhi, E.PhiR = phiFast; else, E.PhiR = nan(n,1); end
            if okX, E.X = xFast; else, E.X = nan(n,1); end
            if okY, E.Y = yFast; else, E.Y = nan(n,1); end
            if okZ, E.Z = zFast; else, E.Z = nan(n,1); end
            if okScatter, E.ScatterType = scatterFast; else, E.ScatterType = repmat({''},n,1); end
            if okPath, E.PathClass = pathFast; else, E.PathClass = repmat({''},n,1); end
            if okPathId, E.PathClassID = pathIdFast; else, E.PathClassID = nan(n,1); end

            badPhi = ~isfinite(E.PhiR) & isfinite(E.X) & isfinite(E.Y) & isfinite(recvRange);
            E.PhiR(badPhi) = atan2d(E.Y(badPhi),E.X(badPhi)-recvRange);
            checkBTRCancelLocal(cancelFlagFile);
            notifyBTRStatusLocal(statusFcn,'BTR 事件整理进度：100%。');
            return;
        end
    catch
        % Continue with the fully compatible scalar fallback.
    end

    E.Delay = nan(n, 1);
    E.ComplexGain = complex(nan(n, 1));
    E.PhiR = nan(n, 1);
    E.X = nan(n, 1);
    E.Y = nan(n, 1);
    E.Z = nan(n, 1);
    E.ScatterType = repmat({''}, n, 1);
    E.PathClass = repmat({''}, n, 1);
    E.PathClassID = nan(n, 1);

    hasX = isfield(EventTable, 'X');
    hasY = isfield(EventTable, 'Y');

    prepProgressPct = -10;
    for ii = 1:n
        if ii == 1 || mod(ii,4096) == 0
            checkBTRCancelLocal(cancelFlagFile);
        end
        E.Delay(ii) = getStructScalarLocal(EventTable(ii), {'Delay','delay'}, nan);

        cg = getStructScalarLocal(EventTable(ii), {'ComplexGain','Gain','Amp'}, []);
        if isempty(cg)
            pg = getStructScalarLocal(EventTable(ii), {'PowerGain','Power'}, nan);
            cg = sqrt(max(pg, 0));
        end
        E.ComplexGain(ii) = cg;

        E.X(ii) = getStructScalarLocal(EventTable(ii), {'X','x'}, nan);
        E.Y(ii) = getStructScalarLocal(EventTable(ii), {'Y','y'}, nan);
        E.Z(ii) = getStructScalarLocal(EventTable(ii), {'Z','z','Depth','ScatterDepth'}, nan);

        phi = getStructScalarLocal(EventTable(ii), {'PhiR','phiR','Bearing','ArrivalAzimuth','Azimuth'}, nan);
        if ~isfinite(phi) && hasX && hasY && isfinite(recvRange)
            phi = atan2d(E.Y(ii), E.X(ii) - recvRange);
        end
        E.PhiR(ii) = phi;

        if isfield(EventTable, 'ScatterType') && ~isempty(EventTable(ii).ScatterType)
            E.ScatterType{ii} = char(EventTable(ii).ScatterType);
        elseif isfield(EventTable, 'Type') && ~isempty(EventTable(ii).Type)
            E.ScatterType{ii} = char(EventTable(ii).Type);
        end

        if isfield(EventTable, 'PathClass') && ~isempty(EventTable(ii).PathClass)
            E.PathClass{ii} = char(EventTable(ii).PathClass);
        elseif isfield(EventTable, 'PathType') && ~isempty(EventTable(ii).PathType)
            E.PathClass{ii} = char(EventTable(ii).PathType);
        end

        E.PathClassID(ii) = getStructScalarLocal(EventTable(ii), ...
            {'PathClassID','pathClassID','PathID'}, nan);
        prepProgressPct = reportBTRProgressLocal( ...
            'BTR 事件整理',ii,n,prepProgressPct,statusFcn);
    end
end

function [values,found] = getStructNumericVectorFastLocal(S,fieldNames,n)
    values = [];
    found = false;
    for kk = 1:numel(fieldNames)
        fieldName = fieldNames{kk};
        if ~isfield(S,fieldName)
            continue;
        end
        try
            raw = [S.(fieldName)];
            if isnumeric(raw) && numel(raw) == n
                values = reshape(raw,[],1);
                found = true;
                return;
            end
        catch
        end
    end
end

function [values,found] = getStructTextVectorFastLocal(S,fieldNames,n)
    values = {};
    found = false;
    for kk = 1:numel(fieldNames)
        fieldName = fieldNames{kk};
        if ~isfield(S,fieldName)
            continue;
        end
        try
            raw = {S.(fieldName)};
            if numel(raw) ~= n
                continue;
            end
            if all(cellfun(@(x) isempty(x) || ischar(x),raw))
                values = reshape(raw,[],1);
                found = true;
                return;
            end
            if all(cellfun(@(x) isempty(x) || ischar(x) || ...
                    (isstring(x) && isscalar(x)),raw))
                values = cellfun(@(x) char(string(x)),raw(:),'UniformOutput',false);
                found = true;
                return;
            end
        catch
        end
    end
end

function E = applyEventMaskLocal(E, mask)
    if isfield(E,'ReceivePathRecords'),E.ReceivePathRecords=E.ReceivePathRecords(mask);end
    E.Delay = E.Delay(mask);
    E.ComplexGain = E.ComplexGain(mask);
    E.PhiR = E.PhiR(mask);
    E.X = E.X(mask);
    E.Y = E.Y(mask);
    E.Z = E.Z(mask);
    if isfield(E, 'ScatterType') && ~isempty(E.ScatterType)
        E.ScatterType = E.ScatterType(mask);
    end
    if isfield(E, 'PathClass') && ~isempty(E.PathClass)
        E.PathClass = E.PathClass(mask);
    end
    if isfield(E, 'PathClassID') && ~isempty(E.PathClassID)
        E.PathClassID = E.PathClassID(mask);
    end
end

function mask = makePathClassMaskLocal(pathClass, filterValue)
    n = numel(pathClass);
    mask = true(n, 1);

    if isempty(filterValue)
        return;
    end

    if ischar(filterValue)
        filterCell = {filterValue};
    elseif isstring(filterValue)
        filterCell = cellstr(filterValue(:));
    elseif iscell(filterValue)
        filterCell = filterValue(:);
    else
        error('BTRfromEvents:InvalidPathClassFilter', ...
            'PathClassFilter 必须是 char、string 或 cell array。');
    end

    filterCell = filterCell(~cellfun(@isempty, filterCell));
    if isempty(filterCell)
        return;
    end
    if any(strcmpi(strtrim(filterCell), 'all'))
        mask = true(n, 1);
        return;
    end

    if isstring(pathClass)
        pathCell = cellstr(pathClass(:));
    elseif ischar(pathClass)
        pathCell = cellstr(pathClass);
    elseif iscell(pathClass)
        pathCell = pathClass(:);
    else
        pathCell = cellstr(string(pathClass(:)));
    end

    pathCell = lower(strtrim(pathCell));
    filterCell = lower(strtrim(filterCell));
    mask = ismember(pathCell, filterCell);
end

function tf = isAllFilterLocal(filterValue)
    tf = false;
    if ischar(filterValue)
        tf = strcmpi(strtrim(filterValue), 'all');
    elseif isstring(filterValue)
        tf = any(strcmpi(strtrim(cellstr(filterValue(:))), 'all'));
    elseif iscell(filterValue)
        try
            tf = any(strcmpi(strtrim(filterValue(:)), 'all'));
        catch
            tf = false;
        end
    end
end

function txBTR = prepareTxForBTRLocal(tx, Fs, BTRFs)
    txBTR = [];
    if isempty(tx)
        return;
    end
    tx = tx(:).';
    if numel(tx) == 1
        txBTR = tx;
        return;
    end

    tOld = (0:numel(tx)-1) / double(Fs);
    tNew = 0 : 1/double(BTRFs) : tOld(end);
    txBTR = interp1(tOld, tx, tNew, 'linear', 0);
    maxVal = max(abs(txBTR));
    if maxVal > 0
        txBTR = txBTR / maxVal;
    end
end

function f0 = estimateDominantFreqLocal(tx, Fs)
    f0 = [];
    if isempty(tx) || numel(tx) < 8
        return;
    end
    tx = double(real(tx(:)));
    tx = tx - mean(tx);
    nfft = 2^nextpow2(numel(tx));
    Y = abs(fft(tx, nfft));
    f = (0:nfft-1).' * double(Fs) / nfft;
    half = 2:floor(nfft/2); % skip DC
    if isempty(half)
        return;
    end
    [~, idx] = max(Y(half));
    f0 = f(half(idx));
end

function val = getFirstFieldLocal(S, names, defaultVal)
    val = defaultVal;
    if ~isstruct(S)
        return;
    end
    for kk = 1:numel(names)
        if isfield(S, names{kk}) && ~isempty(S.(names{kk}))
            val = S.(names{kk});
            return;
        end
    end
end

function val = getFieldOrDefaultLocal(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        val = S.(fieldName);
    else
        val = defaultVal;
    end
end

function val = getStructScalarLocal(s, names, defaultVal)
    val = defaultVal;
    for kk = 1:numel(names)
        if isfield(s, names{kk}) && ~isempty(s.(names{kk}))
            raw = s.(names{kk});
            if isnumeric(raw) || islogical(raw)
                val = raw(1);
            else
                val = raw;
            end
            return;
        end
    end
end

function val = getTableFieldLocal(T, names)
    val = [];
    vars = T.Properties.VariableNames;
    for kk = 1:numel(names)
        hit = strcmp(vars, names{kk});
        if any(hit)
            val = T.(names{kk});
            val = val(:);
            return;
        end
    end
end

function c = getTableCellstrLocal(T, names)
    c = repmat({''}, height(T), 1);
    vars = T.Properties.VariableNames;
    for kk = 1:numel(names)
        hit = strcmp(vars, names{kk});
        if any(hit)
            raw = T.(names{kk});
            if iscell(raw)
                c = raw(:);
            elseif isstring(raw)
                c = cellstr(raw(:));
            elseif ischar(raw)
                c = cellstr(raw);
            else
                c = cellstr(string(raw(:)));
            end
            return;
        end
    end
end

function BTRInfo = makeInfoLocal(numInput, numUsed, numDirectExcluded, numPathClassExcluded, ArrayGeom, BTRParams, BTRFs, fBeam, cLocal, status)
    BTRInfo = struct();
    BTRInfo.Status = status;
    BTRInfo.NumInputEvents = numInput;
    BTRInfo.NumUsedEvents = numUsed;
    BTRInfo.NumDirectExcluded = numDirectExcluded;
    BTRInfo.NumPathClassExcluded = numPathClassExcluded;
    BTRInfo.NArray = ArrayGeom.N;
    BTRInfo.ArraySpacing = ArrayGeom.d;
    BTRInfo.RecvRange = ArrayGeom.RecvRange;
    BTRInfo.Rd = ArrayGeom.Rd;
    BTRInfo.BTRFs = BTRFs;
    BTRInfo.TimeStep = 1 / BTRFs;
    BTRInfo.fBeam = fBeam;
    BTRInfo.cLocal = cLocal;
    BTRInfo.IncludeDirect = logical(getFieldOrDefaultLocal(BTRParams, 'IncludeDirect', false));
end

function lastPct = reportBTRProgressLocal(stageName,completed,total,lastPct,statusFcn)
    if total <= 0
        return;
    end
    pct = min(100,max(0,floor(100 * double(completed) / double(total))));
    reportPct = min(100,10 * floor(pct / 10));
    if completed >= total
        reportPct = 100;
    end
    if reportPct > lastPct
        notifyBTRStatusLocal(statusFcn,sprintf('%s进度：%d%%。',stageName,reportPct));
        lastPct = reportPct;
    end
end

function notifyBTRStatusLocal(statusFcn,msg)
    disp(msg);
    if ~isempty(statusFcn) && isa(statusFcn,'function_handle')
        try
            statusFcn(msg);
        catch
            % Status reporting must not interrupt numerical synthesis.
        end
    end
end

function out = ternaryLocal(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end
