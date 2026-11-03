function [files,products,manifestFile] = generate_dependency_manifest(outputDir)
%generate_dependency_manifest Analyze the true compiled entry point.
if nargin<1||isempty(outputDir),outputDir=pwd;end
[files,products]=matlab.codetools.requiredFilesAndProducts('ZSDXReverbExeMain.m');
files=sort(files(:)); manifestFile=fullfile(outputDir,'requiredFilesAndProducts.txt');
fid=fopen(manifestFile,'w','n','UTF-8'); if fid<0,error('Cannot write %s.',manifestFile);end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'Entry: ZSDXReverbExeMain.m\n\nRequired files:\n');
for k=1:numel(files),fprintf(fid,'%s\n',files{k});end
fprintf(fid,'\nRequired products:\n');
for k=1:numel(products),fprintf(fid,'%s | %s | %s\n',products(k).Name,products(k).Version,products(k).ProductNumber);end
fprintf(fid,'\nExplicit non-MATLAB assets:\n%s\n',fullfile(pwd,'bellhop.exe'));
end
