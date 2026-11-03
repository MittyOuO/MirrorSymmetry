function info = ResolveSeaSurfaceWind(seaState, windSpeedMps)
%RESOLVESEASURFACEWIND 将蒲福海况等级解析为NRL海面散射使用的10 m风速。
% 若显式风速位于所选海况的标准区间内，则保留实测/人工风速；否则采用
% 该海况区间的代表值。这样只修改seaState时，海面气泡云附加量也会随之变化。

validateattributes(seaState,{'numeric'}, ...
    {'scalar','real','finite','integer','>=',0,'<=',12},mfilename,'seaState');
validateattributes(windSpeedMps,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'},mfilename,'windSpeedMps');

% NOAA/WMO蒲福风级的10 m风速区间（m/s）。12级仅规定下限，因此给出
% 34.8 m/s作为数值代表值，同时允许任何不低于32.7 m/s的显式输入。
lower=[0 0.3 1.6 3.4 5.5 8.0 10.8 13.9 17.2 20.8 24.5 28.5 32.7];
upper=[0.2 1.5 3.3 5.4 7.9 10.7 13.8 17.1 20.7 24.4 28.4 32.6 inf];
representative=[0.1 0.9 2.45 4.4 6.7 9.35 12.3 15.5 18.95 22.6 26.45 30.55 34.8];

idx=double(seaState)+1;
withinRange=windSpeedMps>=lower(idx) && windSpeedMps<=upper(idx);
if withinRange
    effectiveWind=double(windSpeedMps);
    source='explicit_wind_within_sea_state_range';
else
    effectiveWind=representative(idx);
    source='sea_state_representative_wind';
end
info=struct('SeaState',double(seaState), ...
    'InputWindSpeedMps',double(windSpeedMps), ...
    'EffectiveWindSpeedMps',effectiveWind, ...
    'StandardWindRangeMps',[lower(idx) upper(idx)], ...
    'RepresentativeWindSpeedMps',representative(idx), ...
    'ResolutionSource',source);
end
