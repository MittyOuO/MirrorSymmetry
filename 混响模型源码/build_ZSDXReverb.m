function packageDir = build_ZSDXReverb()
%build_ZSDXReverb Compile and assemble the theta-batch runtime package.
% Use only the proven toolbox search paths; avoid incidental DSP/Simulink
% dependencies from other installed toolboxes.
root=pwd; savedPath=path; pathCleanup=onCleanup(@() path(savedPath)); %#ok<NASGU>
restoredefaultpath; addpath(root,'-begin'); buildRoot=fullfile(root,'build'); packageDir=fullfile(buildRoot,'package');
% Restrict the actual MATLAB path too. Product-wide -p can otherwise retain
% unrelated shared DSP/Simulink folders from the development installation.
pathParts=strsplit(path,pathsep);
allowedRoots={root,fullfile(matlabroot,'toolbox','matlab'), ...
    fullfile(matlabroot,'toolbox','local'),fullfile(matlabroot,'toolbox','compiler'), ...
    fullfile(matlabroot,'toolbox','shared','supportpkgservices'), ...
    fullfile(matlabroot,'toolbox','shared','coder'), ...
    fullfile(matlabroot,'toolbox','shared','coderutilities'), ...
    fullfile(matlabroot,'toolbox','eml'), ...
    fullfile(matlabroot,'toolbox','parallel'), ...
    fullfile(matlabroot,'toolbox','signal','signal'), ...
    fullfile(matlabroot,'toolbox','stats','stats')};
keep=false(size(pathParts));
for n=1:numel(allowedRoots)
    keep=keep | strcmpi(pathParts,allowedRoots{n}) | ...
        startsWith(lower(pathParts),[lower(allowedRoots{n}) filesep]);
end
path(strjoin(pathParts(keep),pathsep));
if ~exist(buildRoot,'dir'), mkdir(buildRoot); end
if exist(packageDir,'dir')
    resolved=char(java.io.File(packageDir).getCanonicalPath());
    expected=char(java.io.File(fullfile(root,'build','package')).getCanonicalPath());
    if ~strcmpi(resolved,expected),error('Unsafe package path: %s',resolved);end
    rmdir(packageDir,'s');
end
mkdir(packageDir);
WriteParameterReference(root);
generate_dependency_manifest(root);
args={'-m','ZSDXReverbExeMain.m','-o','ZSDXReverb','-d',packageDir, ...
    '-v','-N', ...
    '-I',fullfile(matlabroot,'toolbox','signal','signal'), ...
    '-I',fullfile(matlabroot,'toolbox','stats','stats'), ...
    '-a',fullfile(root,'env'),'-a',fullfile(root,'bellhop.exe'),'-a',fullfile(root,'ParanConfigToZS.json'), ...
    '-a',fullfile(root,'ParameterReference.md'),'-a',fullfile(root,'ParameterCatalog.json'), ...
    '-a',fullfile(root,'ResolveBeamOpenAngle.m'), ...
    '-a',fullfile(root,'BTRfromEvents.m'), ...
    '-a',fullfile(root,'BuildHLASteeringVector.m'), ...
    '-a',fullfile(root,'BuildTowedArrayGeometry.m'), ...
    '-a',fullfile(root,'ComputeEventArrayPhase.m'), ...
    '-a',fullfile(root,'ValidateTowedArrayGeometry.m')};
parallelPaths=pathParts(startsWith(lower(pathParts),lower(fullfile(matlabroot,'toolbox','parallel'))));
coderPaths=pathParts(startsWith(lower(pathParts),lower(fullfile(matlabroot,'toolbox','shared','coder'))) | ...
    startsWith(lower(pathParts),lower(fullfile(matlabroot,'toolbox','eml'))));
parallelPaths=[parallelPaths coderPaths];
for n=1:numel(parallelPaths)
    args=[args {'-I',parallelPaths{n}}]; %#ok<AGROW>
end
mcc(args{:});
% These checks inspect the compiler's real output; do not rewrite the
% dependency metadata to make a build appear compatible.
dependencyInfo=jsondecode(fileread(fullfile(packageDir,'buildresult.json')));
expectedIDs=[35000 35002 35003 35010 35108 35119 35180];
actualIDs=sort([dependencyInfo.RuntimeDependencies.ID]);
assert(isequal(actualIDs,expectedIDs), ...
    'build_ZSDXReverb:RuntimeDependencies', ...
    'Unexpected Runtime dependency set: %s',mat2str(actualIDs));
unresolvedLines=strtrim(splitlines(string(fileread(fullfile(packageDir,'unresolvedSymbols.txt')))));
assert(nnz(strlength(unresolvedLines)>0)==1, ...
    'build_ZSDXReverb:UnresolvedSymbols','Compiler left unresolved symbols.');
copyfile(fullfile(root,'bellhop.exe'),packageDir,'f');
copyfile(fullfile(root,'ParanConfigToZS.json'),packageDir,'f');
copyfile(fullfile(root,'ParameterReference.md'),packageDir,'f');
copyfile(fullfile(root,'ParameterCatalog.json'),packageDir,'f');
copyfile(fullfile(root,'ResolveBeamOpenAngle.m'),packageDir,'f');
copyfile(fullfile(root,'readZSDX.m'),packageDir,'f');
copyfile(fullfile(root,'run_ParanConfigToZS.ps1'),packageDir,'f');
copyfile(fullfile(root,'run_ParanConfigToZS.cmd'),packageDir,'f');
copyfile(fullfile(root,'README.md'),packageDir,'f');
copyfile(fullfile(root,'DELIVERY_NOTES.md'),packageDir,'f');
copyfile(fullfile(root,'JSON_Field_Migration.md'),packageDir,'f');
validationFiles={'RunBTRValidationStandalone.m','ValidateBTRPair.m', ...
    'GetDefaultBTRPeakValidationParams.m','ExtractBTRPeaks.m','MatchBTRPeaks.m'};
for k=1:numel(validationFiles)
    copyfile(fullfile(root,validationFiles{k}),packageDir,'f');
end
if isfile(fullfile(root,'readZSDX_example.json')),copyfile(fullfile(root,'readZSDX_example.json'),packageDir,'f');end
if isfile(fullfile(root,'内置环境参数输入对照表.docx')),copyfile(fullfile(root,'内置环境参数输入对照表.docx'),packageDir,'f');end
copyfile(fullfile(root,'requiredFilesAndProducts.txt'),packageDir,'f');
verificationDir=fullfile(packageDir,'verification'); mkdir(verificationDir);
reportNames={'automatic_frequency_test_report.json','unit_test_report.json', ...
    'beam_mapping_report.json','surface_btr_test_report.json', ...
    'btr_wideband_acceptance_report.json','BTRWidebandSmoke_20260920.json', ...
    'BeamWeight_FASTRL_SecondRound_20260920.json'};
for k=1:numel(reportNames)
    sourceFile=fullfile(root,'tests',reportNames{k});
    if isfile(sourceFile),copyfile(sourceFile,verificationDir,'f');end
end
copyfile(fullfile(root,'env'),fullfile(packageDir,'env'),'f');
if exist(fullfile(root,'signals'),'dir'),copyfile(fullfile(root,'signals'),fullfile(packageDir,'signals'),'f');end
mkdir(fullfile(packageDir,'work'));
copyfile(fullfile(root,'CheckRuntimeCompatibility.ps1'),packageDir,'f');
copyfile(fullfile(root,'RUNTIME_COMPATIBILITY_20261010.md'),packageDir,'f');
fprintf('Package created: %s\n',packageDir);
end
