function Channels = ResolveFrequencyChannels(InputParams)
%ResolveFrequencyChannels Automatically choose one or two propagation frequencies.
%
% CW/HFM/LFM uses one propagation response.  For a CW+HFM composite, the
% CW frequency is compared with the inclusive HFM band:
%   * CW inside the HFM band  -> one response calculated at fCW.  The full
%     composite waveform is retained, so the HFM is still synthesized with
%     its original swept-frequency waveform.
%   * CW outside the HFM band -> two responses, one for each component.
%     Both responses are evaluated during the same scatter-grid traversal.
if ~isstruct(InputParams) || ~isfield(InputParams, 'TxSigInput')
    error('ResolveFrequencyChannels:MissingSignal', ...
        'InputParams.TxSigInput is required.');
end

[txFull, txTime, sigMeta, components] = GenerateTxSignal(InputParams.TxSigInput);
base = struct('Index', 0, 'Name', '', 'ReferenceFrequency', 0, ...
    'SignalType', '', 'SignalStartTime', 0, 'SignalDuration', 0, ...
    'TxSigInput', struct(), 'TxWaveform', [], 'TxTime', [], ...
    'ModeApplied', '', 'DecisionReason', '', 'HfmBand', [], ...
    'CwFrequency', []);

[useSharedComposite, decision, hfmBand, cwFrequency] = ...
    automaticDecisionLocal(InputParams.TxSigInput, components);

if numel(components) == 1 || useSharedComposite
    Channels = base;
    Channels.Index = 1;
    Channels.ReferenceFrequency = sharedFrequencyLocal(InputParams, components);
    Channels.SignalType = sigMeta.sigType;
    Channels.SignalStartTime = 0;
    Channels.SignalDuration = numel(txFull) / sigMeta.fsSig;
    Channels.TxSigInput = InputParams.TxSigInput;
    Channels.TxSigInput.normalizeMode = 'none';
    Channels.TxWaveform = txFull(:);
    Channels.TxTime = txTime(:);
    Channels.ModeApplied = 'automatic_single_frequency';
    Channels.DecisionReason = decision;
    Channels.HfmBand = hfmBand;
    Channels.CwFrequency = cwFrequency;
    if useSharedComposite
        Channels.Name = 'COMPOSITE_SHARED_AT_CW';
    else
        Channels.Name = upper(char(components(1).Type));
    end
    return;
end

Channels = repmat(base, numel(components), 1);
for k = 1:numel(components)
    c = components(k);
    Channels(k).Index = k;
    Channels(k).Name = upper(char(c.Type));
    Channels(k).ReferenceFrequency = c.ReferenceFrequency;
    Channels(k).SignalType = c.Type;
    Channels(k).SignalStartTime = c.StartTime;
    Channels(k).SignalDuration = c.Duration;
    Channels(k).TxWaveform = c.Waveform(:);
    Channels(k).TxTime = c.Time(:);
    Channels(k).ModeApplied = 'automatic_two_frequencies';
    Channels(k).DecisionReason = decision;
    Channels(k).HfmBand = hfmBand;
    Channels(k).CwFrequency = cwFrequency;
    Channels(k).TxSigInput = struct('sigType', 'custom', ...
        'fsSig', sigMeta.fsSig, 'customSignal', c.Waveform(:), ...
        'customFs', sigMeta.fsSig, 'normalizeMode', 'none');
end
end

function [shared, reason, hfmBand, fCW] = automaticDecisionLocal(S, components)
types = upper(string({components.Type}));
idxCW = find(types == "CW", 1, 'first');
idxHFM = find(types == "HFM", 1, 'first');
hfmBand = [];
fCW = [];

if numel(components) == 1
    shared = false;
    reason = 'single_signal_component';
    return;
end

if numel(components) == 2 && ~isempty(idxCW) && ~isempty(idxHFM)
    fCW = double(components(idxCW).ReferenceFrequency);
    if ~isfield(S, 'fStart') || isempty(S.fStart) || ...
            ~isfield(S, 'fEnd') || isempty(S.fEnd)
        error('ResolveFrequencyChannels:MissingHfmBand', ...
            'A CW/HFM composite requires fStart and fEnd.');
    end
    hfmBand = sort([double(S.fStart) double(S.fEnd)]);
    shared = fCW >= hfmBand(1) && fCW <= hfmBand(2);
    if shared
        reason = 'cw_inside_hfm_band_shared_response_at_cw';
    else
        reason = 'cw_outside_hfm_band_separate_responses';
    end
    return;
end

% Other multi-component signal definitions do not have an approved shared
% propagation rule, so keep one response per component.
shared = false;
reason = 'multi_component_without_shared_rule';
end

function f = sharedFrequencyLocal(InputParams, components)
S = InputParams.TxSigInput;
types = upper(string({components.Type}));
idxCW = find(types == "CW", 1, 'first');
if ~isempty(idxCW)
    f = components(idxCW).ReferenceFrequency;
elseif isfield(S, 'fStart') && isfield(S, 'fEnd') && ...
        ~isempty(S.fStart) && ~isempty(S.fEnd)
    f = (double(S.fStart) + double(S.fEnd)) / 2;
elseif numel(components) == 1 && isfinite(components(1).ReferenceFrequency)
    f = components(1).ReferenceFrequency;
elseif isfield(InputParams, 'f0') && ~isempty(InputParams.f0)
    f = double(InputParams.f0);
else
    error('ResolveFrequencyChannels:NoReferenceFrequency', ...
        'Cannot determine the propagation reference frequency.');
end
validateattributes(f, {'numeric'}, {'scalar','real','finite','positive'});
end
