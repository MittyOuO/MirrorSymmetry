function y = ApplyAuditedStableBandpass(x,F,representation)
% Release-external audit helper; it does not modify the frozen release.
arguments
    x {mustBeNumeric}
    F (1,1) struct
    representation (1,1) string {mustBeMember(representation,["DIRECT","SOS","CTF"])}
end
x=x(:);
switch representation
    case "DIRECT"
        y=filtfilt(F.b,F.a,x);
    case "SOS"
        y=filtfilt(F.sos,F.gSOS,x);
    case "CTF"
        y=filtfilt({F.B,F.A,F.gCTF},x);
end
end
