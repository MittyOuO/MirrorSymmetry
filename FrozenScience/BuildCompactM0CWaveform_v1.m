function hM0C = BuildCompactM0CWaveform_v1(hM2Plus,hM2Axis)
%BuildCompactM0CWaveform_v1 Algebraic raw M0-C reconstruction.
% The frozen model copies positive-side delay and ComplexGain exactly to
% the mirror branch; therefore hMinusM0C equals hPlusM2 mathematically.
arguments
    hM2Plus {mustBeNumeric}
    hM2Axis {mustBeNumeric}
end
assert(isvector(hM2Plus)&&isvector(hM2Axis)&&numel(hM2Plus)==numel(hM2Axis), ...
    'G4CR:WaveformShape','hPlus and hAxis must be equal-length vectors.');
assert(all(isfinite(real(hM2Plus(:))))&&all(isfinite(imag(hM2Plus(:))))&& ...
    all(isfinite(real(hM2Axis(:))))&&all(isfinite(imag(hM2Axis(:)))), ...
    'G4CR:WaveformFinite','Raw side responses must be finite.');
shape=size(hM2Plus);
hM0C=reshape(2*double(hM2Plus(:))+double(hM2Axis(:)),shape);
end
