function [DeltaTau,RelativeGain,Meta] = ComputeReceivePathOffsets(Events,G,c,mode)
% Path-specific receive offsets, exp(+iwt), XYZ depth positive down.
% No PhiR/chord fallback. ComplexGain must be depropagated at CenterXYZ.
% terminal_k: RxTerminalKhat (forward facet->receiver) for EACH ordered path.
% exact_element_delays: RxElementDeltaTau_s and RxElementGainRelative.
% Full frequency-dependent Green belongs in a separate frequency operator;
% it must never be multiplied by this propagation phase/delay a second time.
if istable(Events),Events=table2struct(Events);end
if ~isstruct(Events),error('ReceivePath:InvalidEvents','Events must be struct/table.');end
mode=lower(char(string(mode)));
if ~ismember(mode,{'terminal_k','exact_element_delays'})
    error('ReceivePath:UnsupportedMode','Use terminal_k or exact_element_delays; full complex Green cannot be delayed again.');
end
validateattributes(c,{'numeric'},{'scalar','finite','positive'});
xyz=double(G.ElementXYZ);center=double(G.CenterXYZ(:).');
validateattributes(xyz,{'numeric'},{'2d','ncols',3,'finite'});
validateattributes(center,{'numeric'},{'size',[1 3],'finite'});
n=numel(Events);N=size(xyz,1);DeltaTau=zeros(N,n);RelativeGain=complex(ones(N,n));
ids=strings(n,1);pairs=strings(n,1);
required={'EventID','FacetID','TxPathInstanceID','RxPathInstanceID', ...
 'RxPathSourceSHA256','RxLegDirection','RxReflectionSequence', ...
 'RxReferenceXYZ','PhaseConvention','RxGainConvention'};
for i=1:n
    e=Events(i);
    for j=1:numel(required)
        if ~isfield(e,required{j}),error('ReceivePath:PendingSource','Missing %s for event %d.',required{j},i);end
    end
    ids(i)=scalarText(e.EventID);pairs(i)=string(jsonencode({scalarText(e.FacetID),scalarText(e.TxPathInstanceID),scalarText(e.RxPathInstanceID)}));
    if strlength(ids(i))==0 || strlength(scalarText(e.TxPathInstanceID))==0 || strlength(scalarText(e.RxPathInstanceID))==0
        error('ReceivePath:PendingIdentity','Empty ordered identity.');
    end
    if isempty(regexp(char(string(e.RxPathSourceSHA256)),'^[0-9a-fA-F]{64}$','once'))
        error('ReceivePath:PendingSource','A source SHA256 is required.');
    end
    if ~strcmp(e.RxLegDirection,'facet_to_receiver') || ~strcmp(e.PhaseConvention,'exp(+iwt)') || ~strcmp(e.RxGainConvention,'DEPROPAGATED_CENTER')
        error('ReceivePath:Convention','Explicit forward direction, exp(+iwt), and DEPROPAGATED_CENTER required.');
    end
    ref=double(e.RxReferenceXYZ(:).');
    if numel(ref)~=3 || any(~isfinite(ref)) || max(abs(ref-center))>1e-9
        error('ReceivePath:GeometryMismatch','Path center differs from actual array center.');
    end
    if strcmp(mode,'terminal_k')
        if ~isfield(e,'RxTerminalKhat'),error('ReceivePath:PendingSource','Missing terminal k; no geometric fallback.');end
        khat=double(e.RxTerminalKhat(:));
        if numel(khat)~=3 || any(~isfinite(khat)) || abs(norm(khat)-1)>1e-10
            error('ReceivePath:InvalidK','Each path needs one finite unit k vector.');
        end
        DeltaTau(:,i)=(xyz-center)*khat/double(c);
    else
        if ~isfield(e,'RxElementDeltaTau_s') || ~isfield(e,'RxElementGainRelative')
            error('ReceivePath:PendingSource','Exact per-element delays and depropagated relative gains required.');
        end
        dt=double(e.RxElementDeltaTau_s(:));a=double(e.RxElementGainRelative(:));
        if numel(dt)~=N || numel(a)~=N || any(~isfinite(dt)) || any(~isfinite(a))
            error('ReceivePath:InvalidElementData','Per-element data must match every actual array element.');
        end
        DeltaTau(:,i)=dt;RelativeGain(:,i)=a;
    end
end
if numel(unique(ids))~=n || numel(unique(pairs))~=n
    error('ReceivePath:DuplicateIdentity','EventID and facet+ordered Tx/Rx pair must be unique.');
end
Meta=struct('ReceivePhaseMode',mode,'PhaseConvention','exp(+iwt)', ...
 'DelayApplication','full_analytic_passband_fractional_delay_once_no_extra_carrier', ...
 'GeometricFallback',false,'NumEvents',n,'NumElements',N, ...
 'PhysicalQualification','METADATA_VALIDATED_NOT_PHYSICAL_CERTIFICATION');
end
function s=scalarText(x)
s=string(x);
if ~isscalar(s) || ismissing(s),error('ReceivePath:InvalidIdentity','Identity must be one scalar.');end
end
