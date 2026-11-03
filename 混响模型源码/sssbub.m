function ss = sssbub(f,cw,U,theta_in,theta_out)
%
% (NRL Code 7144; January 2003)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Predicts bubble-cloud scattering strength ss = sssbub (dB) 
% as a function of:
%   - acoustic frequency: f (Hz) (<= 5000)
%   - sound speed in bubble-free water at the air-sea interface: cw (m/s)
%   - instantaneous wind speed at an elevation of 10 m: U (m/s)
%   - incident grazing angle: theta_in (deg)
%   - scattered grazing angle: theta_out (deg)
% [Assumes incoherent, transversely isotropic scattering. 
%  Expression is independent of the bistatic scattering angle.]
%
%------------------------------------------------------------------------
% This semi-empirical formula models the dependence of scattering
% strength on bubble-cloud properties via the mean air-void fraction 
% e-folding depth d (m) which, in turn, is parameterized completely by 
% the wind speed U (m/s) via an empirical expression of David Farmer 
% and Svein Vagle (IOS, Canada) (personal communication, 1998). 
% Their empirical CST-7 Phase-2 formula for d as a function of U
% was modified so that below a cut-off of U = 7.5, d linearly -> 0 
% as U -> 3 (with d = 0 for U <= 3).  
%            THIS IMPLIES THAT sssbub = 0 for U < 3.
%
% MKS units are used throughout.
% Angles are always in degrees.
% 
%--------------------------------------------------------------------------
% References: 
% (1) Gauss and Fialkowksi, "A Broadband Model for Predicting Bistatic
%     Surface Scattering Strengths," Proceedings of the Fifth European
%     Conference on Underwater Acoustics, pp. 1165-1170 (2000).
% (2) R.C. Gauss, R.F. Gragg, R.W. Nero, D. Wurmser, and J.M. Fialkowski,
%     "Broadband Models for Predicting Bistatic Bottom, Surface, 
%     and Volume Scattering Strengths," NRL/FR/7100--02-10,042, 
%     Naval Research Laboratory, Washington DC, September 30, 2002.
%
% POC: Dr. Roger Gauss, Naval Research Laboratory, Code 7144
%      Washington, DC 20375-5350    (202-767-3524)
%      roger.gauss@nrl.navy.mil
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Compute d given U
d = zeros(size(U));
idx = U>3&U<7.5;
d(idx) = 0.292625*((U(idx)-3)/4.5);
idx = U>=7.5;
d(idx) = 0.557-0.117*U(idx)+0.0109*U(idx).^2;
%
omega = 2*pi*f;
kw = omega./cw;
%
S = sin(pi*(theta_in/180));
R = sin(pi*(theta_out/180));
%
S2 = S.^2;
R2 = R.^2;
%
A = (kw.*d/2).*S;
B = (kw.*d/2).*R;
%
A2 = A.^2;
B2 = B.^2;
%
X = S2.*R2.*(3+6*(A2+B2)+8*(A2-B2).^2);
Y = (1+4*A2).*(1+4*B2).*(1+4*(A-B).^2).*(1+4*(A+B).^2);
%
ss = 0.0019*(kw.^3.43).*(d.^5.15).*(X./Y);
%
idx = ss > 0;
ss(idx) = 10*log10(ss(idx));
ss(~idx) = nan;
%
