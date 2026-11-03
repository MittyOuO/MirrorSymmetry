function SSP = ValidateAndFormatSSP(rawSSP)
%ValidateAndFormatSSP Return sorted unique finite [depth,speed] pairs.
if ~isnumeric(rawSSP) || size(rawSSP,2) < 2
    error('ValidateAndFormatSSP:InvalidData', 'SSP must be a numeric N-by-2 array.');
end
SSP = double(rawSSP(:,1:2));
SSP = SSP(all(isfinite(SSP),2),:);
if size(SSP,1) < 2, error('ValidateAndFormatSSP:TooShort', 'SSP needs at least two finite rows.'); end
if any(SSP(:,1) < 0) || any(SSP(:,2) <= 0)
    error('ValidateAndFormatSSP:InvalidValues', 'SSP depth must be >=0 and sound speed must be >0.');
end
SSP = sortrows(SSP,1);
[~,idx] = unique(SSP(:,1),'last');
SSP = SSP(sort(idx),:);
if any(diff(SSP(:,1)) <= 0), error('ValidateAndFormatSSP:DepthOrder', 'SSP depths must strictly increase.'); end
if SSP(1,1) > 0
    SSP = [0 SSP(1,2); SSP];
end
end
