function F=G4PairingForensics_v1(M0C,M2)
% 复用冻结 pairing tuple 的逐字格式；只补计数/样例，不改事件或配对函数。
F=struct('IdentityTupleVersion','G4_COMMON_EVENT_TUPLE_v1','CommonPlus',stats(keys(M0C,1),keys(M2,1)), ...
    'Axis',stats(keys(M0C,0),keys(M2,0)));
F.AxisCountedOnce=F.Axis.DuplicateM0C==0 && F.Axis.DuplicateM2==0;
F.PASS=F.CommonPlus.MissingM0C==0 && F.CommonPlus.MissingM2==0 && ...
    F.CommonPlus.DuplicateM0C==0 && F.CommonPlus.DuplicateM2==0 && ...
    F.Axis.MissingM0C==0 && F.Axis.MissingM2==0 && F.AxisCountedOnce;
end
function out=keys(events,sideFilter)
required={'Y','CellKey','PathInstanceKey','PathClass','InterfaceType','DelayIn','DelayOut','NumBotIn','NumTopIn','NumBotOut','NumTopOut'};
for k=1:numel(required),assert(isfield(events,required{k}),'G4PB:PairingFieldMissing','%s',required{k});end
if sideFilter==1,events=events([events.Y]>0);else,events=events([events.Y]==0);end
out=strings(numel(events),1);
for k=1:numel(events)
    e=events(k);side='AXIS';if e.Y>0,side='PLUS';elseif e.Y<0,side='MINUS';end
    out(k)=string(sprintf(['side=%s|cell=%s|path=%s|class=%s|interface=%s|', ...
        'delayIn=%.17g|delayOut=%.17g|Bi=%.17g|Ti=%.17g|Bo=%.17g|To=%.17g'], ...
        side,char(string(e.CellKey)),char(string(e.PathInstanceKey)), ...
        char(string(e.PathClass)),char(string(e.InterfaceType)),double(e.DelayIn), ...
        double(e.DelayOut),double(e.NumBotIn),double(e.NumTopIn),double(e.NumBotOut),double(e.NumTopOut)));
end
out=sort(out);
end
function S=stats(a,b)
% unique+accumarray 避免逐键扫描整个生产事件表。
[u,~,ix]=unique([a;b]);ca=zeros(numel(u),1);cb=ca;
if ~isempty(a),ca=accumarray(reshape(ix(1:numel(a)),[],1),1,[numel(u),1]);end
if ~isempty(b),cb=accumarray(reshape(ix(numel(a)+1:end),[],1),1,[numel(u),1]);end
miss0=max(cb-ca,0);miss2=max(ca-cb,0);
bad=u(ca~=cb | ca>1 | cb>1);bad=bad(1:min(10,numel(bad)));
S=struct('CountM0C',numel(a),'CountM2',numel(b),'ExactMatchedCount',sum(min(ca,cb)), ...
    'MissingM0C',sum(miss0),'MissingM2',sum(miss2), ...
    'DuplicateM0C',sum(max(ca-1,0)),'DuplicateM2',sum(max(cb-1,0)), ...
    'MismatchKeyExamples',{cellstr(bad)});
end
