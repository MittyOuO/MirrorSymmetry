function cellKey = BuildScatterCellKey(interfaceType, gridX, gridY)
%BuildScatterCellKey Stable identifier of one signed physical interface cell.

interfaceType = lower(strtrim(char(string(interfaceType))));
cellKey = sprintf('%s|x=%+.17g|y=%+.17g', ...
    interfaceType, double(gridX), double(gridY));
end

