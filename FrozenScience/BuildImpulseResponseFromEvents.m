function h = BuildImpulseResponseFromEvents(EventTable, fs, nPoints)
%BuildImpulseResponseFromEvents Bin one immutable event table into h(t).

validateattributes(fs, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(nPoints, {'numeric'}, {'scalar','real','finite','integer','positive'});
h = complex(zeros(1, double(nPoints)));
if isempty(EventTable)
    return;
end

if istable(EventTable)
    delay = double(EventTable.Delay(:));
    gain = EventTable.ComplexGain(:);
elseif isstruct(EventTable)
    delay = reshape(double([EventTable.Delay]), [], 1);
    gain = reshape([EventTable.ComplexGain], [], 1);
else
    error('BuildImpulseResponseFromEvents:InvalidEventTable', ...
        'EventTable must be a struct array or table.');
end

index = round(delay * double(fs)) + 1;
gain = double(gain);
valid = isfinite(delay) & isfinite(real(gain)) & isfinite(imag(gain)) & ...
    index >= 1 & index <= double(nPoints);
index = index(valid);
gain = gain(valid);
if isempty(index)
    return;
end

% The event order is deterministic; accumulate real and imaginary parts
% separately for broad MATLAB-version compatibility.
hReal = accumarray(index, real(gain), [double(nPoints), 1], @sum, 0);
hImag = accumarray(index, imag(gain), [double(nPoints), 1], @sum, 0);
h = complex(hReal, hImag).';
end
