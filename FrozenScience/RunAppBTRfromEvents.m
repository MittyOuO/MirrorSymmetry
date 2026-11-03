function [BTR,timeAxis,scanAngles,BTRInfo] = RunAppBTRfromEvents( ...
        EventTable,ArrayGeom,TxSignalForSim,Fs,BTRParams)
%RunAppBTRfromEvents Call the App-owned optimized BTR implementation.
%
% The project also contains an older Re\BTRfromEvents.m.  MATLAB gives the
% current folder priority over added paths, so an App launched while the
% current folder is Re can otherwise execute that old implementation.  The
% uniquely named bridge temporarily makes this Code folder current and
% verifies the resolved implementation before starting the long synthesis.

codeDir = fileparts(mfilename('fullpath'));
expectedFile = fullfile(codeDir,'BTRfromEvents.m');
oldDir = pwd;
cleanupDir = onCleanup(@() cd(oldDir));

cd(codeDir);
addpath(codeDir,'-begin');
clear BTRfromEvents
rehash path

resolvedFile = which('BTRfromEvents');
if isempty(resolvedFile) || ~strcmpi(resolvedFile,expectedFile)
    error('RunAppBTRfromEvents:WrongImplementation', ...
        'App BTR implementation resolution failed. Expected %s, resolved %s.', ...
        expectedFile,resolvedFile);
end

[BTR,timeAxis,scanAngles,BTRInfo] = BTRfromEvents( ...
    EventTable,ArrayGeom,TxSignalForSim,Fs,BTRParams);

if ~isstruct(BTRInfo)
    BTRInfo = struct('RawInfo',BTRInfo);
end
BTRInfo.AppImplementationFile = expectedFile;
end
