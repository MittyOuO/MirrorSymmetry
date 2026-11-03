function ChannelResult = ReconstructElementSignalFromEvents(Results, InputParams, elementIndex)
% ReconstructElementSignalFromEvents
% Fast single-channel reconstruction from a saved event table.
% This function does NOT rerun Bellhop / ImpulseResponse. It only changes the
% receiver element position and rebuilds h(t), y(t), and RL(t).

    if nargin < 3 || isempty(elementIndex)
        elementIndex = getFirstField(InputParams, {'DisplayElement','DisplayElementIndex'}, 1);
    end
    elementIndex = round(double(elementIndex));

    fs = getFirstField(InputParams, {'fs','Fs'}, getFirstField(Results, {'fs','fsCalc'}, 3000));
    f0 = getFirstField(InputParams, {'f0','F0','fCenter'}, 500);
    B  = getFirstField(InputParams, {'B','Bandwidth'}, 0);
    Itg = getFirstField(InputParams, {'Itg','itg'}, 0.02);
    TWindow = getFirstField(InputParams, {'TWindow','TWindowCompute','TWindowDisplay'}, 50);
    SpreadTime = getFirstField(InputParams, {'SpreadTime'}, 0);

    NArray = round(getFirstField(InputParams, {'NArray','NumElements'}, 1));
    d = getFirstField(InputParams, {'ArraySpacing','d'}, 0);
    firstRange = getFirstField(InputParams, {'FirstArrayRange','FirstElementRange'}, []);

    % Reference range used when the saved event table was generated.
    if isfield(Results, 'InputParams') && isstruct(Results.InputParams) && isfield(Results.InputParams, 'RecvRange')
        refRange = Results.InputParams.RecvRange;
    else
        refRange = getFirstField(InputParams, {'RecvRange'}, []);
    end

    if isempty(firstRange) || ~isfinite(firstRange)
        if NArray > 1 && isfinite(d)
            firstRange = refRange - ((NArray - 1) / 2) * d;
        else
            firstRange = refRange;
        end
    end
    targetRange = firstRange + (elementIndex - 1) * d;

    cLocal = getLocalC(InputParams, targetRange);
    k = 2*pi*f0/cLocal;
    nPts = max(1, ceil(TWindow * fs) + 1);

    EventSca = getScatterEvents(Results);
    EventDir = getDirectEvents(Results);

    mode=getFirstField(InputParams,{'ReceivePhaseMode'},'legacy_geometric');
    if isfield(InputParams,'BTR') && isfield(InputParams.BTR,'ReceivePhaseMode'),mode=InputParams.BTR.ReceivePhaseMode;end
    if ismember(lower(char(string(mode))),{'terminal_k','exact_element_delays'})
        geom=BuildTowedArrayGeometry(InputParams);
        hSca=buildPathIR(EventSca,nPts,fs,geom,elementIndex,cLocal,mode);
        hDir=buildPathIR(EventDir,nPts,fs,geom,elementIndex,cLocal,mode);
    elseif strcmpi(mode,'legacy_geometric')
        hSca = buildIR(EventSca, nPts, fs, refRange, targetRange, cLocal, k, false);
        hDir = buildIR(EventDir, nPts, fs, refRange, targetRange, cLocal, k, true);
    else
        error('ReceivePath:UnsupportedMode','Unsupported reconstruction mode.');
    end

    % Use the project ApplyTimeSmearing if available. Support both the new
    % ApplyTimeSmearing(hSca,hDir,SpreadTime,InputParams) interface and the old
    % ApplyTimeSmearing(hSca,hDir,SpreadTime,f0,B,fs,Itg) interface.
    TxForSim = [];
    try
        [yDir, ySca, timeRt, TxForSim] = ApplyTimeSmearing(hSca, hDir, SpreadTime, InputParams);
    catch ME
        if isApplyTimeSmearingInterfaceError(ME)
            [yDir, ySca, timeRt, TxForSim] = ApplyTimeSmearing(hSca, hDir, SpreadTime, f0, B, fs, Itg);
        else
            rethrow(ME);
        end
    end

    yTotal = yDir(:) + ySca(:);
    timeRt = timeRt(:);

    RLParams = InputParams;
    RLParams.InputMode = 'model';
    if ~isfield(RLParams, 'SourceLevel') && isfield(RLParams, 'SL')
        RLParams.SourceLevel = RLParams.SL;
    end
    try
        [RLCurve, timeRL] = ComputeRLCurveFromVoltage(yTotal, fs, RLParams);
    catch
        RLCurve = [];
        timeRL = [];
    end

    ChannelResult = struct();
    ChannelResult.ElementIndex = elementIndex;
    ChannelResult.ReferenceRange = refRange;
    ChannelResult.TargetRange = targetRange;
    ChannelResult.hSca = hSca;
    ChannelResult.hDir = hDir;
    ChannelResult.yDir = yDir;
    ChannelResult.ySca = ySca;
    ChannelResult.yTotal = yTotal;
    ChannelResult.timeRt = timeRt;
    ChannelResult.RLCurve = RLCurve;
    ChannelResult.timeRL = timeRL;
    ChannelResult.TxForSim = TxForSim;
    ChannelResult.ReceivePhaseMode=char(string(mode));
    ChannelResult.ReceivePathPhysicalQualification='NOT_INFERRED_FROM_RECONSTRUCTION';
    ChannelResult.NumScatterEvents = numel(EventSca);
    ChannelResult.NumDirectEvents = numel(EventDir);
end

function h = buildIR(E, nPts, fs, refRange, targetRange, cLocal, k, isDirect)
    h = complex(zeros(nPts, 1));
    if isempty(E)
        return;
    end
    dxElem = targetRange - refRange;
    for ii = 1:numel(E)
        delay0 = getEventScalar(E(ii), {'Delay','delay'}, NaN);
        gain0 = getEventScalar(E(ii), {'ComplexGain','Gain','Amp'}, []);
        if isempty(gain0)
            pg = getEventScalar(E(ii), {'PowerGain','Power'}, NaN);
            if isfinite(pg)
                gain0 = sqrt(max(pg, 0));
            else
                gain0 = NaN;
            end
        end
        if ~isfinite(delay0) || ~isfinite(real(gain0)) || ~isfinite(imag(gain0))
            continue;
        end

        if isDirect
            % Direct/specular path fallback: the receiver moves along the range axis.
            deltaR = dxElem;
        else
            x = getEventScalar(E(ii), {'X','x'}, NaN);
            y = getEventScalar(E(ii), {'Y','y'}, NaN);
            if isfinite(x) && isfinite(y)
                rRef = hypot(double(x) - double(refRange), double(y));
                rTar = hypot(double(x) - double(targetRange), double(y));
                deltaR = rTar - rRef;
            else
                phi = getEventScalar(E(ii), {'PhiR','phiR','Bearing','ArrivalAzimuth','Azimuth'}, NaN);
                if isfinite(phi)
                    deltaR = -dxElem * cosd(phi);
                else
                    deltaR = 0;
                end
            end
        end

        delayNew = delay0 + deltaR / cLocal;
        idx = round(delayNew * fs) + 1;
        if idx >= 1 && idx <= nPts
            h(idx) = h(idx) + gain0 .* exp(-1i * k * deltaR);
        end
    end
end

function E = getScatterEvents(R)
    E = [];
    if isfield(R, 'EventTable') && ~isempty(R.EventTable)
        E = R.EventTable(:);
    else
        if isfield(R, 'EventTableBottom') && ~isempty(R.EventTableBottom)
            E = [E; R.EventTableBottom(:)]; %#ok<AGROW>
        end
        if isfield(R, 'EventTableSurface') && ~isempty(R.EventTableSurface)
            E = [E; R.EventTableSurface(:)]; %#ok<AGROW>
        end
    end
end

function E = getDirectEvents(R)
    E = [];
    if isfield(R, 'EventTableDirect') && ~isempty(R.EventTableDirect)
        E = R.EventTableDirect(:);
    end
end

function c = getLocalC(P, ~)
    c = 1500;
    if isfield(P, 'SSP') && isnumeric(P.SSP) && size(P.SSP,2) >= 2
        depth = getFirstField(P, {'Rd'}, P.SSP(1,1));
        try
            c = interp1(P.SSP(:,1), P.SSP(:,2), depth, 'linear', 'extrap');
        catch
            c = 1500;
        end
    end
    if ~isfinite(c) || c <= 0
        c = 1500;
    end
end

function v = getFirstField(S, names, defaultVal)
    v = defaultVal;
    if ~isstruct(S)
        return;
    end
    for jj = 1:numel(names)
        name = names{jj};
        if isfield(S, name) && ~isempty(S.(name))
            v = S.(name);
            return;
        end
    end
end

function v = getEventScalar(E, names, defaultVal)
    v = defaultVal;
    for jj = 1:numel(names)
        name = names{jj};
        if isfield(E, name) && ~isempty(E.(name))
            tmp = E.(name);
            if isnumeric(tmp) || islogical(tmp)
                v = tmp(1);
            else
                v = tmp;
            end
            return;
        end
    end
end

function tf = isApplyTimeSmearingInterfaceError(ME)
    msg = string(ME.message);
    id = string(ME.identifier);
    tf = contains(id, "TooManyInputs") || ...
        contains(id, "NotEnoughInputs") || ...
        contains(msg, "输入参数太多") || ...
        contains(msg, "Too many input arguments") || ...
        contains(msg, "Not enough input arguments");
end

function h=buildPathIR(E,nPts,fs,G,m,c,mode)
h=complex(zeros(nPts,1));
if isempty(E),return;end
[dt,relative]=ComputeReceivePathOffsets(E,G,c,mode);
if m<1 || m>size(dt,1),error('ReceivePath:ElementIndex','Element index outside actual geometry.');end
for i=1:numel(E)
    position=(double(E(i).Delay)+dt(m,i))*fs;base=floor(position);a=position-base;
    coeff=[-a*(a-1)*(a-2)/6,(a+1)*(a-1)*(a-2)/2,-(a+1)*a*(a-2)/2,(a+1)*a*(a-1)/6];
    for j=1:4
        index=base+j-2+1;
        if index>=1 && index<=nPts
            % Full waveform convolution applies propagation delay once.
            h(index)=h(index)+coeff(j)*double(E(i).ComplexGain)*relative(m,i);
        end
    end
end
end
