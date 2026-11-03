function [PropagationChannels, Jobs, DispatchInfo] = PreparePropagationChannels(InputParams, Channels, OptionBorder, TempWorkDir)
%PreparePropagationChannels Run all independent BELLHOP paths concurrently.
%
% The function first writes every frequency/path environment file. It then
% starts one bellhop.exe operating-system process per path without creating
% a MATLAB parallel pool. When automatic selection produces two frequencies,
% all paths for both frequencies therefore run together. Arrival files are
% parsed only after every process finishes.

nCh = numel(Channels);
if isfield(InputParams,'DomainResolved') && isstruct(InputParams.DomainResolved)
    bottomDomain=InputParams.DomainResolved;
else
    [bottomDomain,~]=ResolveBottomDomain(InputParams,'channels');
end
cancelFlagFile = getFieldOrDefaultLocal(InputParams,'CancelFlagFile','');
PropagationChannels = repmat( ...
    struct( ...
        'Frequency',0, ...
        'WorkDir','', ...
        'Bottom',struct(), ...
        'BottomEnvironmentAudit',struct(), ...
        'Surface',struct(), ...
        'SurfaceSoundSpeed',NaN), ...
    nCh,1);

specTemplate = struct( ...
    'channelIndex',0, ...
    'frequency',0, ...
    'workDir','', ...
    'baseName','', ...
    'pathType','');
jobSpecs = repmat(specTemplate,0,1);

%% 1. Write all frequency-specific BELLHOP environments

for ch = 1:nCh
    frequency = Channels(ch).ReferenceFrequency;
    chDir = fullfile( ...
        TempWorkDir, ...
        sprintf('F%02d_%gHz',ch,frequency));

    if ~exist(chDir,'dir')
        mkdir(chDir);
    end

    envAudit=ResetEnvBottom( ...
        frequency, ...
        InputParams.Sd, ...
        InputParams.Rd, ...
        InputParams.Sediment, ...
        chDir, ...
        InputParams.SSP, ...
        InputParams.Beam, ...
        bottomDomain.PropagationSpec, ...
        InputParams.WaterDepth);

    PropagationChannels(ch).Frequency = frequency;
    PropagationChannels(ch).WorkDir = chDir;
    PropagationChannels(ch).BottomEnvironmentAudit = envAudit;

    jobSpecs(end+1,1) = makeSpecLocal( ... %#ok<AGROW>
        ch,frequency,chDir,'Bottom_StoB','Bottom.SourceToBottom');
    jobSpecs(end+1,1) = makeSpecLocal( ... %#ok<AGROW>
        ch,frequency,chDir,'Bottom_BtoR','Bottom.BottomToReceiver');
    jobSpecs(end+1,1) = makeSpecLocal( ... %#ok<AGROW>
        ch,frequency,chDir,'Bottom_StoR','Bottom.SourceToReceiver');

    if OptionBorder == 0
        PropagationChannels(ch).SurfaceSoundSpeed = ResetEnvTop( ...
            frequency, ...
            InputParams.Sd, ...
            InputParams.Rd, ...
            InputParams.Sediment, ...
            chDir, ...
            InputParams.SSP, ...
            InputParams.Beam, ...
            InputParams.Rmax, ...
            InputParams.RecvRange, ...
            InputParams.WaterDepth);

        jobSpecs(end+1,1) = makeSpecLocal( ... %#ok<AGROW>
            ch,frequency,chDir,'Surface_StoT','Surface.SourceToSurface');
        jobSpecs(end+1,1) = makeSpecLocal( ... %#ok<AGROW>
            ch,frequency,chDir,'Surface_RtoT','Surface.SurfaceToReceiver');
    end
end

%% 2. Build job records and locate the packaged BELLHOP executable

nJobs = numel(jobSpecs);
emptyJob = struct( ...
    'channelIndex',0, ...
    'frequency',0, ...
    'pathType','', ...
    'envFile','', ...
    'arrFile','', ...
    'elapsedTime',0, ...
    'success',false, ...
    'message','');

Jobs = repmat(emptyJob,nJobs,1);

for jobIndex = 1:nJobs
    spec = jobSpecs(jobIndex);
    Jobs(jobIndex) = makeJobLocal(spec);
end

bellhopExecutable = which('bellhop.exe');

if isempty(bellhopExecutable)
    error( ...
        'PreparePropagationChannels:BellhopNotFound', ...
        'bellhop.exe was not found in the MATLAB/deployed application path.');
end

%% 3. Launch every bellhop.exe process before waiting for any one of them

dispatchTimer = tic;
processes = cell(nJobs,1);

fprintf( ...
    'Launching %d BELLHOP jobs as concurrent OS processes.\n', ...
    nJobs);

for jobIndex = 1:nJobs
    spec = jobSpecs(jobIndex);

    startInfo = System.Diagnostics.ProcessStartInfo();
    startInfo.FileName = bellhopExecutable;
    startInfo.Arguments = spec.baseName;
    startInfo.WorkingDirectory = spec.workDir;
    startInfo.UseShellExecute = false;
    startInfo.CreateNoWindow = true;
    startInfo.RedirectStandardOutput = false;
    startInfo.RedirectStandardError = false;

    process = System.Diagnostics.Process();
    process.StartInfo = startInfo;

    if ~process.Start()
        error( ...
            'PreparePropagationChannels:ProcessStartFailed', ...
            'Could not start BELLHOP job %s.', ...
            spec.pathType);
    end

    processes{jobIndex} = process;
end

%% 4. Wait for every process and validate all arrival files

failedMessages = {};

for jobIndex = 1:nJobs
    process = processes{jobIndex};
    while ~process.HasExited
        drawnow limitrate;
        if cancelFlagExistsLocal(cancelFlagFile)
            terminateProcessesLocal(processes);
            error('Reverb:ModelRunStopped','用户已请求停止运行。');
        end
        pause(0.05);
    end

    duration = process.ExitTime.Subtract(process.StartTime);
    Jobs(jobIndex).elapsedTime = duration.TotalSeconds;

    if process.ExitCode ~= 0
        Jobs(jobIndex).message = sprintf( ...
            'bellhop.exe exit code %d', ...
            process.ExitCode);
        failedMessages{end+1} = sprintf( ... %#ok<AGROW>
            '%s: %s', ...
            Jobs(jobIndex).pathType, ...
            Jobs(jobIndex).message);
    elseif ~isfile(Jobs(jobIndex).arrFile)
        Jobs(jobIndex).message = sprintf( ...
            'BELLHOP did not create %s.', ...
            Jobs(jobIndex).arrFile);
        failedMessages{end+1} = sprintf( ... %#ok<AGROW>
            '%s: %s', ...
            Jobs(jobIndex).pathType, ...
            Jobs(jobIndex).message);
    else
        Jobs(jobIndex).success = true;
    end

    process.Dispose();
end

dispatchWallTime = toc(dispatchTimer);

if ~isempty(failedMessages)
    error( ...
        'PreparePropagationChannels:BellhopFailed', ...
        'One or more BELLHOP jobs failed: %s', ...
        strjoin(failedMessages,' | '));
end

%% 5. Parse completed arrivals and assemble frequency-channel structures

for jobIndex = 1:nJobs
    [arrivals,~] = read_arrivals_asc(Jobs(jobIndex).arrFile);
    ch = Jobs(jobIndex).channelIndex;

    switch Jobs(jobIndex).pathType
        case 'Bottom.SourceToBottom'
            PropagationChannels(ch).Bottom.SourceToBottom = arrivals;

        case 'Bottom.BottomToReceiver'
            PropagationChannels(ch).Bottom.BottomToReceiver = arrivals;

        case 'Bottom.SourceToReceiver'
            PropagationChannels(ch).Bottom.SourceToReceiver = arrivals;

        case 'Surface.SourceToSurface'
            PropagationChannels(ch).Surface.SourceToSurface = arrivals;

        case 'Surface.SurfaceToReceiver'
            PropagationChannels(ch).Surface.SurfaceToReceiver = arrivals;

        otherwise
            error( ...
                'PreparePropagationChannels:UnknownPathType', ...
                'Unknown BELLHOP path type: %s', ...
                Jobs(jobIndex).pathType);
    end
end

jobElapsedSum = sum([Jobs.elapsedTime]);
DispatchInfo = struct( ...
    'ExecutionMode','parallel_external_processes', ...
    'JobCount',nJobs, ...
    'WorkerCount',nJobs, ...
    'PoolCreatedByRun',false, ...
    'PoolMessage','No MATLAB pool; direct asynchronous bellhop.exe launch.', ...
    'WallTime',dispatchWallTime, ...
    'SumOfJobElapsedTime',jobElapsedSum, ...
    'OverlapFactor',jobElapsedSum/max(dispatchWallTime,eps));

fprintf( ...
    ['BELLHOP dispatch complete: %d/%d jobs, mode=%s, ' ...
     'wall=%.3f s, overlap=%.2f.\n'], ...
    sum([Jobs.success]), ...
    nJobs, ...
    DispatchInfo.ExecutionMode, ...
    dispatchWallTime, ...
    DispatchInfo.OverlapFactor);

end

function tf = cancelFlagExistsLocal(flagFile)
tf = ~isempty(flagFile) && exist(char(string(flagFile)),'file') == 2;
end

function terminateProcessesLocal(processes)
for k = 1:numel(processes)
    p = processes{k};
    if isempty(p)
        continue;
    end
    try
        if ~p.HasExited
            p.Kill();
            p.WaitForExit();
        end
    catch
    end
    try
        p.Dispose();
    catch
    end
end
end

function value = getFieldOrDefaultLocal(S,name,defaultValue)
if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
    value = S.(name);
else
    value = defaultValue;
end
end

function spec = makeSpecLocal(ch,frequency,workDir,baseName,pathType)
%makeSpecLocal Store one independent BELLHOP path calculation.

spec = struct( ...
    'channelIndex',ch, ...
    'frequency',frequency, ...
    'workDir',workDir, ...
    'baseName',baseName, ...
    'pathType',pathType);

end

function job = makeJobLocal(spec)
%makeJobLocal Create the audit record for one BELLHOP process.

job = struct( ...
    'channelIndex',spec.channelIndex, ...
    'frequency',spec.frequency, ...
    'pathType',spec.pathType, ...
    'envFile',fullfile(spec.workDir,[spec.baseName '.env']), ...
    'arrFile',fullfile(spec.workDir,[spec.baseName '.arr']), ...
    'elapsedTime',0, ...
    'success',false, ...
    'message','');

end
