function beta=ComputeEventBeamCoordinate(E,G,steeringMode)
% Beam coordinate agrees with the receiving steering geometry and sign.
if nargin<3,steeringMode='nominal_horizontal';end
p=G.ElementXYZ;
axis=p(end,:)-p(1,:);axis=axis/max(norm(axis),eps);
if istable(E),q=[E.X,E.Y,E.Z];else,q=[[E.X].',[E.Y].',[E.Z].'];end
r=q-G.CenterXYZ;u=(r*axis.') ./ max(vecnorm(r,2,2),eps);
if strcmpi(steeringMode,'geometry_matched')
    % Actual-coordinate steering still scans horizontal directions; account
    % for the projection of a pitched array axis onto its nominal heading.
    heading=deg2rad(G.ArrayHeadingDeg);projection=axis*[cos(heading);sin(heading);0];
    u=u/max(abs(projection),eps);
end
beta=asind(max(-1,min(1,u)));
end
