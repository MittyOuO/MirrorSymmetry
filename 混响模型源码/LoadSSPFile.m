function rawSSP = LoadSSPFile(fileName)
%LoadSSPFile Load two-column SSP data from MAT/TXT/CSV.
fileName = char(fileName);
if ~isfile(fileName), error('LoadSSPFile:NotFound', 'SSP file not found: %s', fileName); end
[~,~,ext] = fileparts(fileName);
switch lower(ext)
    case '.mat'
        data = load(fileName);
        names = fieldnames(data);
        rawSSP = [];
        for k = 1:numel(names)
            value = data.(names{k});
            if isnumeric(value) && ismatrix(value) && size(value,2) >= 2
                rawSSP = value(:,1:2);
                break;
            end
        end
        if isempty(rawSSP), error('LoadSSPFile:NoMatrix', 'No numeric N-by-2 SSP matrix in %s.', fileName); end
    case {'.txt','.csv'}
        rawSSP = readmatrix(fileName);
    otherwise
        error('LoadSSPFile:InvalidExtension', 'SSP supports only .mat, .txt, and .csv.');
end
end
