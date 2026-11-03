function P = ResolveBTRParameters(raw,fs,nElements,spacing,tWindow,angleStepDeg)
%ResolveBTRParameters Parse public theta angles and return internal beta.
% JSON BTR.ScanAngles is the public array-axis theta convention [0,180].
% BTRfromEvents and all steering kernels continue to use beta=theta-90.
if nargin<1 || isempty(raw),raw=struct();end
if nargin<2 || isempty(fs),error('ResolveBTRParameters:MissingFs','fs is required.');end
if nargin<3 || isempty(nElements),nElements=512;end
if nargin<4 || isempty(spacing),spacing=1.5;end
if nargin<5 || isempty(tWindow),tWindow=50;end
if nargin<6 || isempty(angleStepDeg),angleStepDeg=2;end

P=raw;
P.N=double(fieldOrLocal(raw,'N',nElements));
P.d=double(fieldOrLocal(raw,'d',spacing));
P.TWindow=double(fieldOrLocal(raw,'TWindow',tWindow));
P.BTRFs=double(fieldOrLocal(raw,'BTRFs',min(double(fs),5000)));
if isfield(raw,'TimeStep') && ~isempty(raw.TimeStep),P.BTRFs=1/double(raw.TimeStep);end
if isfield(raw,'ScanAngles') && ~isempty(raw.ScanAngles)
    theta=double(raw.ScanAngles(:).');
else
    step=double(angleStepDeg);
    theta=0:step:180;
    if theta(end)<180-1e-9,theta(end+1)=180;end
end
validateattributes(theta,{'numeric'},{'vector','finite','nonempty','increasing'});
if any(theta < -1e-9 | theta > 180+1e-9)
    error('ResolveBTRParameters:PublicAngleRange', ...
        'Public BTR.ScanAngles must use theta in [0,180] degrees.');
end
P.PublicScanAnglesTheta=theta;
P.ScanAngles=theta-90;
P.PublicAngleConvention='theta_0_180_array_axis_deg';
P.InternalAngleConvention='beta_-90_90_broadside_deg';
P.SmoothTime=double(fieldOrLocal(raw,'SmoothTime',0.1));
P.IncludeDirect=logical(fieldOrLocal(raw,'IncludeDirect',false));
P.NormalizeDB=logical(fieldOrLocal(raw,'NormalizeDB',true));
P.ChunkSize=double(fieldOrLocal(raw,'ChunkSize',2000));
P.PhaseMode='full_3D_HLA';
P.ReceivePhaseMode=char(string(fieldOrLocal(raw,'ReceivePhaseMode','legacy_geometric')));
P.RequireQualifiedReceivePath=logical(fieldOrLocal(raw,'RequireQualifiedReceivePath',false));
P.ApplyElementDelay=true;
P.SteeringMode=char(string(fieldOrLocal(raw,'SteeringMode','nominal_horizontal')));
validateattributes(P.BTRFs,{'numeric'},{'scalar','positive','finite'});
validateattributes(P.SmoothTime,{'numeric'},{'scalar','nonnegative','finite'});
end

function value=fieldOrLocal(S,name,defaultValue)
if isstruct(S)&&isfield(S,name)&&~isempty(S.(name)),value=S.(name);else,value=defaultValue;end
end
