function Audit=VerifyG4SyntheticResponseClosure_v1(hTotal,hPositive,hNegative,hAxis,zTotal,zPositive,zNegative,zAxis,Tolerance)
arguments
    hTotal (:,1) double
    hPositive (:,1) double
    hNegative (:,1) double
    hAxis (:,1) double
    zTotal (:,1) double
    zPositive (:,1) double
    zNegative (:,1) double
    zAxis (:,1) double
    Tolerance (1,1) double {mustBeNonnegative} = 1e-12
end
hScale=max(1,norm(hTotal));zScale=max(1,norm(zTotal));
hResidual=norm(hTotal-(hPositive+hNegative+hAxis))/hScale;
zResidual=norm(zTotal-(zPositive+zNegative+zAxis))/zScale;
assert(hResidual<=Tolerance,'G4Seed1Auth:RawResponseClosure','Raw response closure failed.');
assert(zResidual<=Tolerance,'G4Seed1Auth:ObservedResponseClosure','Observed response closure failed.');
Audit=struct('RawClosureResidual',hResidual,'ObservedClosureResidual',zResidual, ...
    'SameRealizationRequired',true,'SameObserverRequired',true,'PASS',true);
end
