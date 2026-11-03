function T=CompactBTREventTable(E)
% Lossless column storage of the event data actually used by BTR.
if istable(E),T=E;return;end
if isempty(E)
    T=table(zeros(0,1),complex(zeros(0,1)),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
        cell(0,1),cell(0,1),'VariableNames',{'Delay','ComplexGain','X','Y','Z','PhiR','ScatterType','PathClass'});return;
end
T=table([E.Delay].',[E.ComplexGain].',[E.X].',[E.Y].',[E.Z].',[E.PhiR].', ...
    {E.ScatterType}.',{E.PathClass}.','VariableNames', ...
    {'Delay','ComplexGain','X','Y','Z','PhiR','ScatterType','PathClass'});
end
