function ss = sssnrl(f,cw,U,As,gamma2,theta_in,theta_out,phi_out,ssopt)
%
% (NRL Code 7144; January 2003)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Predicts surface scattering strength ss = sssnrl (dB) 
% as a function of:
%   - acoustic frequency: f (Hz)
%   - sound speed in bubble-free water at the air-sea interface: cw (m/s)
%   - instantaneous wind speed at an elevation of 10 m: U (m/s)
%   - surface roughness spectral parameters: w2 (m^4) and gamma2, 
%      where w2 = As*U, with As an empirically-derived scalar: As (m^3-s)
%   - incident grazing angle: theta_in (deg)
%   - scattered grazing angle: theta_out (deg)
%   - scattered bistatic angle: phi_out (deg).
% [Assumes incoherent scattering only and transversely isotropic roughness;
%  hence, there is only one bistatic angle (so we set phi_in = 0 deg).]
%
% Hence, there are 3 environmental parameters: U, As, and gamma2.
% Fits to a variety of open-ocean acoustic data have found that 
% As = 0.00019 and gamma2 = 3.8 work well. Fixing these parameter values
% in SSSRUN, the only environmental input is then the wind speed U.
%
% The max value of 10*log10(sssint) is set to be 0 dB.
%
% MKS units are used throughout.
% Angles are always in degrees.
%
%--------------------------------------------------------------------------
% Surface scattering strength ss in dB = 10.*log10(sssint + ssssbub)
% where the scattering submodels describe:
%  1. Rough Air-Sea Interface Scattering (sssint)
%     Lowest-order Small-Slope Approximation (SSA) for an isotropic,   
%     pure power-law water wave spectrum. 
%  2. Bubble Cloud Scattering (sssbub)
%     Semi-empirical, Lloyd-mirror model of bubble-cloud scattering. 
%
% OPTIONS:
% Can plot     the total surface scattering strength (ssopt = 0), 
%             *or* only the interface component      (ssopt = 1), 
%             *or* only the bubble-cloud component   (ssopt = 2).
% Note for ssopt = 2, f should be <= 5000 Hz and that sssbub = 0 
% for U <= 3.  (In each case, full computations are still done, 
% but just the chosen output is returned by sssnrl.)
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
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Requires that at most one of three input dimension be varied at a time.
% These consist of K-Omega (f or cw), environmental parameters (U, As, 
% or gamma2), and scattering angle (theta_in, theta_out or phi_out).
%
% Multi-valued input parameters are converted to row vectors and 
% scattering strength is returned as a row vector.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% convert input parameters to row vectors
f = f(:)';
cw = cw(:)';
U = U(:)';
As = As(:)';
gamma2 = gamma2(:)';
theta_in = theta_in(:)';
theta_out = theta_out(:)';
phi_out = phi_out(:)';
%
% expand scattering angles
try
   uno = ones(1,max([length(theta_in) length(theta_out) length(phi_out)]));
   theta_in = uno.*theta_in;
   theta_out = uno.*theta_out;
   phi_out = uno.*phi_out;
catch
   error('Restrict input parameters to single dimension')
end
%
% check for multiple dimensions
try
   ndim = 0;
   if (length(f + cw) > 1), ndim = ndim + 1; end
   if (length(U) > 1), ndim = ndim + 1; end
   if (length(theta_in + theta_out + phi_out) > 1), ndim = ndim + 1; end
   if (ndim > 1), error('Restrict input parameters to single dimension'), end
catch
   error('Restrict input parameters to single dimension')
end
%
w2 = As*U;          % spectral strength as a function of wind speed
%
% scattering from rough sea surface
ssi = sssint(f,cw,w2,gamma2,theta_in,theta_out,phi_out);
if ssopt==1
    ss = ssi;
    return
end
%
% scattering from bubble clouds
ssb = sssbub(f,cw,U,theta_in,theta_out);
if ssopt==2
    ss = ssb;
    return
end
%
% combined sea surface scattering
% (convert to linear before adding)
idx = ~isnan(ssi);
ssi(idx) = 10.^(.1*ssi(idx));
ssi(~idx) = 0;
idx = ~isnan(ssb);
ssb(idx) = 10.^(.1*ssb(idx));
ssb(~idx) = 0;
% (now combine and output in dB)
ss = ssi + ssb;
idx = ss > 0;
ss(idx) = 10*log10(ss(idx));
ss(~idx) = nan;
%
