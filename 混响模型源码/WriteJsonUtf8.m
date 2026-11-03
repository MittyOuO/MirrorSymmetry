function WriteJsonUtf8(fileName,value)
%WriteJsonUtf8 Write pretty UTF-8 JSON without BOM.
folder=fileparts(fileName); if ~isempty(folder)&&~exist(folder,'dir'), mkdir(folder); end
try, text=jsonencode(value,'PrettyPrint',true); catch, text=jsonencode(value); end
fid=fopen(fileName,'w','n','UTF-8');
if fid<0, error('WriteJsonUtf8:OpenFailed','Cannot write %s.',fileName); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',text);
end
