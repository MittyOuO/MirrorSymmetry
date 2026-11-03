function [unitValue, numericId, hexId] = StableKeyHash(varargin)
%StableKeyHash Stable SHA-256 based mapping of typed key parts.
%   unitValue is in [0,1). numericId uses the first 48 digest bits and is
%   exactly representable as a MATLAB double. hexId is the full digest.

encoded = cell(size(varargin));
for k = 1:numel(varargin)
    encoded{k} = encodePartLocal(varargin{k});
    encoded{k} = sprintf('%d:%s', numel(encoded{k}), encoded{k});
end
payload = strjoin(encoded, '|');

digest = sha256Local(payload);
bytes = mod(double(digest(:)), 256);
numericId = 0;
for k = 1:6
    numericId = numericId * 256 + bytes(k);
end
unitValue = numericId / 2^48;
hexId = lower(reshape(dec2hex(bytes, 2).', 1, []));
end

function text = encodePartLocal(value)
if isstring(value) || ischar(value)
    text = ['text:', char(join(string(value(:).'), char(31)))];
elseif isnumeric(value) || islogical(value)
    text = sprintf('numeric:%s:%s', class(value), mat2str(value, 17));
elseif isempty(value)
    text = 'empty:';
else
    text = ['other:', char(string(value))];
end
end

function digest = sha256Local(payload)
bytes = unicode2native(payload, 'UTF-8');
try
    md = java.security.MessageDigest.getInstance('SHA-256');
    digest = md.digest(uint8(bytes));
catch ME
    error('StableKeyHash:SHA256Unavailable', ...
        'SHA-256 is required for stable event mapping: %s', ME.message);
end
end

