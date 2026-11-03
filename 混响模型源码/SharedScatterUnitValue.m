function u = SharedScatterUnitValue(varargin)
%SharedScatterUnitValue Return one stable phase basis in [0,1).
%
% This is an internal hash of physical cell/path identifiers, not a random
% seed supplied by JSON. Frequency is intentionally absent from the key, so
% 500 Hz and 700 Hz arrivals belonging to the same cell and path family use
% the same phase basis during the one shared scatter-grid traversal.

key = 0;

for k = 1:numel(varargin)
    value = varargin{k};

    if ischar(value)
        numbers = double(value(:));
    elseif isstring(value)
        numbers = double(char(value));
        numbers = numbers(:);
    elseif isnumeric(value) || islogical(value)
        numbers = double(value(:));
    else
        numbers = double(char(string(value)));
        numbers = numbers(:);
    end

    if isempty(numbers)
        numbers = 0;
    end

    weights = (1:numel(numbers)).';
    key = key + 104729*k + sum((numbers + 37*k).*weights);
end

x = sin(key*12.9898 + 78.233)*43758.5453123;
u = x - floor(x);

if u < 0
    u = u + 1;
elseif u >= 1
    u = u - floor(u);
end

end
