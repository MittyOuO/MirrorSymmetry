function Out=ProjectG4NumericalSubspaceThinQR_v1(V,v)
% Production projector: thin QR only. No SVD and no normal-matrix inverse.
arguments
    V (:,:) double
    v (:,1) double
end
assert(size(V,1)==numel(v),'G4Seed1Auth:ProjectionLengthMismatch','V and v lengths differ.');
[Q,R]=qr(V,0);
tol=max(size(V))*eps(norm(R,2));
rankQR=sum(abs(diag(R))>tol);
assert(rankQR==4,'G4Seed1Auth:NumericalControlRank','Frozen numerical-control rank must be 4.');
parallelQR=Q*(Q'*v);
perpendicularQR=v-parallelQR;
scale=max(1,norm(v));
Out=struct('ProductionProjector',"THIN_QR",'SVDProjectorUse',"QA_CROSSCHECK_ONLY", ...
    'RankQR',rankQR,'QOrthogonalityResidual',norm(Q'*Q-eye(4),'fro'), ...
    'Parallel',parallelQR,'Perpendicular',perpendicularQR, ...
    'ClosureResidual',norm(v-parallelQR-perpendicularQR)/scale);
end
