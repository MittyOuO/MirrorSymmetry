function Out=ComputeG4ContinuousVectorGeometry_v1(vModel,ControlVectors,iC5)
% Prospective continuous geometry only; no binary direction decision.
arguments
    vModel (:,1) double
    ControlVectors (:,:) double
    iC5 (:,1) double
end
assert(size(ControlVectors,2)==4,'G4Seed1Auth:ControlVectorCount','Exactly four control vectors are required.');
assert(size(ControlVectors,1)==numel(vModel)&&numel(iC5)==numel(vModel), ...
    'G4Seed1Auth:VectorGeometryLength','Vector lengths differ.');
mag=norm(vModel);
Out=struct('Magnitude',mag,'DirectionState',"DEFINED_CONTINUOUS_GEOMETRY", ...
    'CosinesToControls',NaN(1,4),'AnglesDegToControls',NaN(1,4), ...
    'MIDDIdentity',"SECONDARY_CONTINUOUS_DIAGNOSTIC",'CosineToIC5',NaN,'AngleDegToIC5',NaN, ...
    'BinaryDirectionThreshold',"PROHIBITED");
if mag==0
    Out.DirectionState="DIRECTION_UNDEFINED_ZERO_VECTOR";
    return
end
for k=1:4
    nk=norm(ControlVectors(:,k));assert(nk>0,'G4Seed1Auth:ZeroControlVector','Control vector is zero.');
    c=max(-1,min(1,(vModel'*ControlVectors(:,k))/(mag*nk)));
    Out.CosinesToControls(k)=c;Out.AnglesDegToControls(k)=acosd(c);
end
ni=norm(iC5);
if ni>0
    c=max(-1,min(1,(vModel'*iC5)/(mag*ni)));
    Out.CosineToIC5=c;Out.AngleDegToIC5=acosd(c);
end
P=ProjectG4NumericalSubspaceThinQR_v1(ControlVectors,vModel);
Out.ProjectionNorm=norm(P.Parallel);Out.OrthogonalResidualNorm=norm(P.Perpendicular);
Out.ProjectionEnergyFraction=(norm(P.Parallel)/mag)^2;
Out.SubspaceAngleDeg=acosd(max(-1,min(1,norm(P.Parallel)/mag)));
end
