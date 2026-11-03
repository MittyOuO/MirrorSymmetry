function [BTRResult, elapsedTime] = BuildOptionalBTRFromEvents( ...
        EventTable, InputParams, NeedBTR, StatusFcn)
%BuildOptionalBTRFromEvents Optional BTR post-processing only.
%   This function never regenerates or mutates events and never builds h(t).

if nargin < 3 || isempty(NeedBTR), NeedBTR = true; end
if nargin < 4, StatusFcn = []; end
timer = tic;
if ~logical(NeedBTR)
    BTRResult = [];
    elapsedTime = toc(timer);
    return;
end
if isempty(EventTable)
    BTRResult = [];
    elapsedTime = toc(timer);
    return;
end

existing = fieldOrLocal(InputParams, 'BTR', []);
if hasValidBTRLocal(existing)
    BTRResult = existing;
    elapsedTime = toc(timer);
    return;
end

arrayGeom = fieldOrLocal(InputParams, 'ArrayGeom', struct());
btrParams = fieldOrLocal(InputParams, 'BTRParams', struct());
btrParams = fillIfMissingLocal(btrParams, 'RecvRange', fieldOrLocal(InputParams, 'RecvRange', NaN));
btrParams = fillIfMissingLocal(btrParams, 'Rd', fieldOrLocal(InputParams, 'Rd', NaN));
btrParams = fillIfMissingLocal(btrParams, 'SSP', fieldOrLocal(InputParams, 'SSP', []));
btrParams = fillIfMissingLocal(btrParams, 'TWindow', ...
    fieldOrLocal(InputParams, 'TWindowCompute', fieldOrLocal(InputParams, 'TWindow', 50)));
btrParams = fillIfMissingLocal(btrParams, 'CancelFlagFile', ...
    fieldOrLocal(InputParams, 'CancelFlagFile', ''));
btrParams = fillIfMissingLocal(btrParams, 'StatusFcn', StatusFcn);

tx = fieldOrLocal(InputParams, 'TxSignalForSim', []);
if isempty(tx), tx = fieldOrLocal(InputParams, 'TxSignal', []); end
if isempty(tx) && isfield(InputParams, 'TxSigInput') && ~isempty(InputParams.TxSigInput)
    [tx, ~] = GenerateTxSignal(InputParams.TxSigInput);
end
fs = fieldOrLocal(InputParams, 'fs', []);

[data, timeAxis, betaHLA, info] = RunAppBTRfromEvents( ...
    EventTable, arrayGeom, tx, fs, btrParams);
info.GeometricAzimuthName = 'PhiR';
info.ScanAngleName = 'BetaHLA';
info.DirectionCosineName = 'DirectionCosineX';
info.LeftRightAmbiguity = true;
info.ObservabilityStatement = [ ...
    'For an x-axis single HLA, mirrored +/-PhiR have the same axial ', ...
    'direction cosine and therefore the same array response.'];
BTRResult = struct('Data', data, 'TimeAxis', timeAxis, ...
    'BetaHLA', betaHLA, 'ScanAngles', betaHLA, 'Info', info);
elapsedTime = toc(timer);
end

function value = fieldOrLocal(S, name, defaultValue)
value = defaultValue;
if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
    value = S.(name);
end
end

function S = fillIfMissingLocal(S, name, value)
if ~isstruct(S), S = struct(); end
if ~isfield(S, name) || isempty(S.(name))
    S.(name) = value;
end
end

function tf = hasValidBTRLocal(data)
tf = ~isempty(data);
if isstruct(data) && isfield(data, 'Data')
    tf = tf && ~isempty(data.Data);
elseif isnumeric(data)
    tf = tf && any(isfinite(data(:)));
end
end

