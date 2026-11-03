function Validation = RunBTRValidationStandalone(simSource,measSource,Options)
%RunBTRValidationStandalone Validate simulated/measured BTR outside the App.
% Sources may be a struct, a MAT file, or a FIG file containing an image.
if nargin<3,Options=struct();end
Sim=loadBTRSourceLocal(simSource,'simulation');
Meas=loadBTRSourceLocal(measSource,'measurement');
Validation=ValidateBTRPair(Sim,Meas,Options);
fprintf('BTR validation status: %s\n',Validation.Status);
if isfinite(Validation.EglobalMs)
    fprintf('Eglobal: %.3f ms (threshold %.3f ms), matches: %d\n', ...
        Validation.EglobalMs,1000*Validation.Params.PassThresholdSec,Validation.MatchCount);
else
    fprintf('Eglobal: NOT_COMPUTED (%s)\n',Validation.Message);
end
end

function Out=loadBTRSourceLocal(source,label)
if isstruct(source)
    Out=coerceStructLocal(source,label);return;
end
if ~(ischar(source)||isstring(source))
    error('RunBTRValidationStandalone:Source','%s source must be a struct, MAT, or FIG.',label);
end
file=char(source);
if ~isfile(file),error('RunBTRValidationStandalone:MissingFile','File not found: %s',file);end
[~,~,ext]=fileparts(file);
switch lower(ext)
    case '.mat'
        Out=coerceStructLocal(load(file),label);
    case '.fig'
        Out=readFigLocal(file,label);
    otherwise
        error('RunBTRValidationStandalone:Extension','Unsupported %s source: %s',label,ext);
end
Out.SourceFile=file;
end

function Out=coerceStructLocal(S,label)
candidates={S};
names=fieldnames(S);
for k=1:numel(names)
    value=S.(names{k});
    if isstruct(value)&&isscalar(value),candidates{end+1}=value;end %#ok<AGROW>
end
for k=1:numel(candidates)
    C=candidates{k};
    b=readAnyLocal(C,{'BTR','BTRData','BTRMatrix'});
    t=readAnyLocal(C,{'timeBTR','timeAxis','Time'});
    a=readAnyLocal(C,{'scanAngles','angles','BeamAngles'});
    if isnumeric(b)&&isnumeric(t)&&isnumeric(a)
        Out=struct('BTR',double(b),'timeBTR',double(t(:)), ...
            'scanAngles',double(a(:).'),'SourceType','MAT_or_struct');
        if size(Out.BTR,1)==numel(Out.timeBTR)&&size(Out.BTR,2)==numel(Out.scanAngles)
            Out.BTR=Out.BTR.';
        end
        return;
    end
end
error('RunBTRValidationStandalone:MATFields', ...
    '%s source does not contain BTR, timeBTR/timeAxis, and scanAngles.',label);
end

function value=readAnyLocal(S,names)
value=[];
for k=1:numel(names)
    if isfield(S,names{k})&&~isempty(S.(names{k})),value=S.(names{k});return;end
end
end

function Out=readFigLocal(file,label)
fig=openfig(file,'invisible');
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
images=findall(fig,'Type','image');
if isempty(images)
    error('RunBTRValidationStandalone:FIGImage','%s FIG has no image object.',label);
end
[~,idx]=max(arrayfun(@(h)numel(h.CData),images));im=images(idx);
C=double(im.CData);ax=ancestor(im,'axes');
x=expandAxisLocal(double(im.XData),size(C,2));
y=expandAxisLocal(double(im.YData),size(C,1));
xlabelText=string(ax.XLabel.String);ylabelText=string(ax.YLabel.String);
if contains(lower(xlabelText),'time')||contains(xlabelText,'时间')
    Out=struct('BTR',C,'timeBTR',x(:),'scanAngles',y(:).','SourceType','FIG');
else
    Out=struct('BTR',C.','timeBTR',y(:),'scanAngles',x(:).','SourceType','FIG');
end
if ~(contains(lower(xlabelText),'angle')||contains(xlabelText,'方位')|| ...
        contains(lower(ylabelText),'time')||contains(ylabelText,'时间'))
    warning('RunBTRValidationStandalone:FIGAxes', ...
        'FIG axis labels are not explicit; assuming X=angle and Y=time.');
end
end

function axisValues=expandAxisLocal(data,n)
data=data(:).';
if numel(data)==n,axisValues=data;
elseif numel(data)==2,axisValues=linspace(data(1),data(2),n);
else,axisValues=1:n;
end
end
