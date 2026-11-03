function [mdFile,jsonFile] = WriteParameterReference(outputDir)
%WriteParameterReference Generate Markdown and JSON from one catalog.
if nargin<1 || isempty(outputDir), outputDir=pwd; end
if ~exist(outputDir,'dir'), mkdir(outputDir); end
catalog=GetParameterCatalog();
jsonFile=fullfile(outputDir,'ParameterCatalog.json'); WriteJsonUtf8(jsonFile,catalog);
mdFile=fullfile(outputDir,'ParameterReference.md');
fid=fopen(mdFile,'w','n','UTF-8'); if fid<0,error('WriteParameterReference:OpenFailed','Cannot write %s.',mdFile);end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'# ZSDXReverb 参数参考\n\n');
fprintf(fid,'本文件与 `ParameterCatalog.json` 由 `GetParameterCatalog.m` 同一数据源生成。\n\n');
fprintf(fid,'| 英文标识 | 中文名称 | JSON 路径 | 允许值 | 默认值 | 单位 | 模型字段 | 物理含义 |\n');
fprintf(fid,'|---|---|---|---|---|---|---|---|\n');
for k=1:numel(catalog)
    fprintf(fid,'| %s | %s | `%s` | %s | %s | %s | `%s` | %s |\n', ...
        catalog(k).englishId,catalog(k).chineseName,catalog(k).jsonPath, ...
        textLocal(catalog(k).allowedValues),textLocal(catalog(k).defaultValue), ...
        catalog(k).unit,catalog(k).modelField,catalog(k).physicalMeaning);
end
end
function out=textLocal(value)
if iscell(value), out=strjoin(cellfun(@textLocal,value,'UniformOutput',false),', ');
elseif islogical(value), out=char(string(value));
elseif isnumeric(value), out=mat2str(value);
else, out=char(string(value)); end
out=strrep(out,'|','\|');
end
