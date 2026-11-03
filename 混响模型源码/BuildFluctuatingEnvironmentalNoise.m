function [vNoise, NLTime_dB, NoiseInfo] = BuildFluctuatingEnvironmentalNoise( ...
    N, FsComp, BaselineNL_dB, Sensitivity_dB, AmpGain_dB, StdDB, Seed, varargin)
%BuildFluctuatingEnvironmentalNoise One reproducible receiver-noise realization.
% The caller must add vNoise to its clean receiver voltage, then calculate
% RL from that same final voltage. This helper never filters measured data.

validateattributes(N, {'numeric'}, {'scalar','integer','nonnegative'}, mfilename, 'N', 1);
validateattributes(FsComp, {'numeric'}, {'scalar','real','finite','positive'}, mfilename, 'FsComp', 2);
validateattributes(BaselineNL_dB, {'numeric'}, {'scalar','real','finite'}, mfilename, 'BaselineNL_dB', 3);
validateattributes(Sensitivity_dB, {'numeric'}, {'scalar','real','finite'}, mfilename, 'Sensitivity_dB', 4);
validateattributes(AmpGain_dB, {'numeric'}, {'scalar','real','finite'}, mfilename, 'AmpGain_dB', 5);
validateattributes(StdDB, {'numeric'}, {'scalar','real','finite','nonnegative'}, mfilename, 'StdDB', 6);
validateattributes(Seed, {'numeric'}, {'scalar','integer','nonnegative'}, mfilename, 'Seed', 7);

N = double(N);
FsComp = double(FsComp);
opts = struct();
if ~isempty(varargin)
    opts = varargin{1};
    if ~isstruct(opts) || ~isscalar(opts)
        error('BuildFluctuatingEnvironmentalNoise:InvalidOptions', ...
            'Optional noise-band metadata must be a scalar struct.');
    end
end
stream = RandStream('mt19937ar', 'Seed', double(Seed));
t = (0:N-1).' / FsComp;
deltaNL = zeros(N,1);
controlTimes = [];
controlIntervalMinSec = 0.035;
controlIntervalMaxSec = 0.065;
if N >= 2 && StdDB > 0
    controlTimes = 0;
    duration = (N-1)/FsComp;
    while controlTimes(end) < duration
        controlTimes(end+1) = controlTimes(end) + ...
            controlIntervalMinSec + ...
            (controlIntervalMaxSec-controlIntervalMinSec)*rand(stream); %#ok<AGROW>
    end
    controlValues = randn(stream, numel(controlTimes), 1);
    deltaNL = interp1(controlTimes(:), controlValues, t, 'pchip');
    deltaNL = deltaNL - mean(deltaNL);
    observedStd = std(deltaNL);
    if observedStd > 0
        deltaNL = deltaNL * (double(StdDB)/observedStd);
    end
end
NLTime_dB = double(BaselineNL_dB) + deltaNL;

unitGaussian = randn(stream, N, 1);
bandAssumption = 'unbandlimited Gaussian receiver-noise realization';
bandApplied = false;
if isfield(opts, 'NoiseBandHz') && ~isempty(opts.NoiseBandHz)
    band = double(opts.NoiseBandHz(:).');
    if numel(band) ~= 2 || any(~isfinite(band)) || ...
            band(1) <= 0 || band(2) <= band(1) || band(2) >= FsComp/2
        error('BuildFluctuatingEnvironmentalNoise:InvalidNoiseBand', ...
            'NoiseBandHz must be [low high] strictly inside (0, FsComp/2).');
    end
    if N < round(FsComp)
        error('BuildFluctuatingEnvironmentalNoise:ShortBandlimitedNoise', ...
            'At least one second is required for explicit band-limited noise.');
    end
    % The deployed JSON/BTR entry never supplies the optional NoiseBandHz.
    % Keep MATLAB behavior; exclude this unused deployment-only dependency.
    %#exclude bandpass
    unitGaussian = bandpass(unitGaussian, band, FsComp);
    unitGaussian = unitGaussian / max(sqrt(mean(unitGaussian.^2)), realmin);
    bandAssumption = sprintf('explicit receiver-noise band [%.6g %.6g] Hz', band);
    bandApplied = true;
end
vNoiseRms = 10.^((NLTime_dB + double(Sensitivity_dB) + double(AmpGain_dB))/20);
vNoise = unitGaussian .* vNoiseRms;

NoiseInfo = struct();
NoiseInfo.Method = 'irregular_control_point_pchip_plus_Gaussian_receiver_noise';
NoiseInfo.Seed = double(Seed);
NoiseInfo.Fs = FsComp;
NoiseInfo.SampleCount = N;
NoiseInfo.BaselineNL_dB = double(BaselineNL_dB);
NoiseInfo.NLJitterStdTarget_dB = double(StdDB);
NoiseInfo.NLJitterStdActual_dB = std(deltaNL);
NoiseInfo.ControlPointCount = numel(controlTimes);
NoiseInfo.ControlPointTimesSec = controlTimes;
NoiseInfo.ControlPointIntervalRangeSec = ...
    [controlIntervalMinSec, controlIntervalMaxSec];
NoiseInfo.ControlPointIntervalsSec = diff(controlTimes);
if numel(controlTimes) >= 2
    intervals = NoiseInfo.ControlPointIntervalsSec;
    NoiseInfo.ControlPointMeanIntervalSec = mean(intervals);
    NoiseInfo.ControlPointIntervalStatsSec = struct( ...
        'Min', min(intervals), 'Median', median(intervals), ...
        'Mean', mean(intervals), 'Max', max(intervals), ...
        'Std', std(intervals));
else
    NoiseInfo.ControlPointMeanIntervalSec = NaN;
    NoiseInfo.ControlPointIntervalStatsSec = struct( ...
        'Min', NaN, 'Median', NaN, 'Mean', NaN, ...
        'Max', NaN, 'Std', NaN);
end
NoiseInfo.BandAssumption = bandAssumption;
NoiseInfo.NoiseBandApplied = bandApplied;
NoiseInfo.MeasuredSignalFiltered = false;
NoiseInfo.GlobalRNGTouched = false;
NoiseInfo.InputUnitContract = 'NL dB re 1 uPa; Sensitivity dB re 1 V/uPa; AmpGain dB';
end
