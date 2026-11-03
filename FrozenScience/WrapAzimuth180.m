function angleDeg = WrapAzimuth180(angleDeg)
%WrapAzimuth180 Normalize directed azimuths to the half-open interval.
%   The unique internal azimuth convention is [-180, 180) degrees.

angleDeg = mod(double(angleDeg) + 180, 360) - 180;
end

