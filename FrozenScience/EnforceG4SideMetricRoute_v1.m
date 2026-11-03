function Audit=EnforceG4SideMetricRoute_v1(MetricName,RequestedOperation)
arguments
    MetricName (1,1) string
    RequestedOperation (1,1) string
end
allowed=["abs(A_E)","D_pm","signed A_E","C_pm"];
assert(any(MetricName==allowed),'G4Seed1Auth:UnauthorizedSideMetric','Unknown side metric.');
assert(RequestedOperation~="SCALAR_R_MODEL",'G4Seed1Auth:SideScalarRmodelProhibited', ...
    'Side scalar R_model and borrowed Dnum routes are prohibited.');
assert(RequestedOperation~="BORROW_TOTAL_DNUM",'G4Seed1Auth:SideDnumBorrowProhibited', ...
    'A total-response Dnum cannot be borrowed for a side metric.');
Audit=struct('MetricName',MetricName,'Operation',RequestedOperation, ...
    'Route',"STOCHASTIC_BRIDGE_NOT_ESTABLISHED",'PASS',true);
end
