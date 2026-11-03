function Tuples=CanonicalG4CommonEventTuple_v2(Events)
%CanonicalG4CommonEventTuple_v2 Byte-exact frozen 11-field tuple formatter.
arguments
    Events (:,1) struct
end
required={'Y','CellKey','PathInstanceKey','PathClass','InterfaceType', ...
    'DelayIn','DelayOut','NumBotIn','NumTopIn','NumBotOut','NumTopOut'};
for k=1:numel(required)
    assert(isfield(Events,required{k}),'G4GCPC:TupleFieldMissing','Missing frozen tuple field %s.',required{k});
end
Tuples=strings(numel(Events),1);
for k=1:numel(Events)
    e=Events(k);side='AXIS';if e.Y>0,side='PLUS';elseif e.Y<0,side='MINUS';end
    Tuples(k)=string(sprintf(['side=%s|cell=%s|path=%s|class=%s|interface=%s|', ...
        'delayIn=%.17g|delayOut=%.17g|Bi=%.17g|Ti=%.17g|Bo=%.17g|To=%.17g'], ...
        side,char(string(e.CellKey)),char(string(e.PathInstanceKey)), ...
        char(string(e.PathClass)),char(string(e.InterfaceType)),double(e.DelayIn), ...
        double(e.DelayOut),double(e.NumBotIn),double(e.NumTopIn), ...
        double(e.NumBotOut),double(e.NumTopOut)));
end
end
