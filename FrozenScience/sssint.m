function ss = sssint(f,cw,w2,gamma2,theta_in,theta_out,phi_out)
%
% (NRL Code 7144; January 2003)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Predicts surface-interface scattering strength ss = sssint (dB) 
% as a function of:
%   - acoustic frequency: f (Hz)
%   - sound speed in bubble-free water at the air-sea interface: cw (m/s)
%   - surface roughness spectral parameters: w2 (m^4) and gamma2
%   - incident grazing angle: theta_in (deg)
%   - scattered grazing angle: theta_out (deg)
%   - scattered bistatic angle: phi_out (deg).
% [Assumes incoherent scattering only and transversely isotropic roughness;
%  hence, there is only one bistatic angle (so we set phi_in = 0 deg).]
%
% The max value of 10.*log10(ss) is set to be 0 dB.
%
%--------------------------------------------------------------------------
% Uses lowest-order small-slope formulation [Gragg et al.,
% JASA 110, 2878-2901 (2001)] consisting of:
% * the asymptotic-series formulation with ntilde = 40 terms 
%    (valid for "small" alpha) "spot-welded" at an
%    empirically determined alpha_tilde to the
% * the rational-function formulation with orders L,M = 6,9 
%    (valid for non-small alpha).
% The result should be reliable in the range 2.4 <= gamma2 <= 3.95.
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
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Requires that at most one of three input parameter dimensions 
% be varied at a time. These consist of:
%   - K-Omega (f and cw)
%   - roughness spectrum (w2 and gamma2)
%   - scattering angle (theta_in, theta_out, and phi_out).
%
% Multi-valued input parameters must be input as row vectors and 
% scattering strength is returned as a row vector.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% normalizing reference distance (1 m)
h0 = 1;
%
% incident bistatic angle
% (set to 0 since assume tranversely isotropic wave spectra)
phi_in = zeros(size(phi_out));
%
% empirical parameters
ntilde = 40;
orders = [6, 9];
alpha_tilde = 10.^(-1.7567*gamma2 + 4.4926); 
%
% secondary quantities
nu = (gamma2-2)/2;   omega = 2*pi*f;   Kw = omega./cw;
hrms = sqrt(pi*w2./nu)/h0;
%
% scattering directions
rtheta_in = pi/2 + pi*(theta_in/180);
rphi_in = pi*(phi_in/180);
u_in = [(sin(rtheta_in).*cos(rphi_in)).' (sin(rtheta_in).*sin(rphi_in)).' (cos(rtheta_in)).'].';
rtheta_out = pi/2 - pi*(theta_out/180);
rphi_out = pi*(phi_out/180);
u_out = [(sin(rtheta_out).*cos(rphi_out)).' (sin(rtheta_out).*sin(rphi_out)).' (cos(rtheta_out)).'].';
%
% wave vectors
k = u_in*Kw;   q = u_out*Kw;   kdotq = dot(k(1:2,:),q(1:2,:));
Q = k - q;   absQhorz = sqrt( dot( Q(1:2,:),Q(1:2,:) ) );
%
% Dashen/Henyey/Wurmser (JASA, 1990) parameter
alpha = (gamma(1-nu)./gamma(1+nu)./4.^nu) .* (hrms*Q(3,:)).^2 ./ (h0*absQhorz).^(2*nu);
%
% surface prefactor
stheta_in = sin(pi*(theta_in/180));
stheta_out = sin(pi*(theta_out/180));
beta = -4*Kw.^2*(stheta_in.*stheta_out);
prefactor = abs(beta./(Q(3,:).*absQhorz)).^2/(8*pi);
%
% integral
integral = zeros(size(alpha));
%
% "small" alpha
idx = alpha < alpha_tilde;
%
% Small-slope asymptotic-series formulation (valid for "small" alpha). 
if any(idx)
%
   n = [1:ntilde]';
   uno = ones(size(alpha));
   np = n*uno;
   nup = n*(nu.*uno);
   X = -cos(pi*np(:,idx));
   Y = sin(pi*nup(:,idx))*2/pi;
   Z = exp( log(4)*nup(:,idx) + 2*gammaln(1+nup(:,idx)) - gammaln(1+n)*uno(idx) + n*log(alpha(idx)) );
   integral(idx) = sum(X.*Y.*Z,1);
%
end
%
% "non-small" alpha
idx = ~idx;
%
% Small-slope rational-function formulation (valid for non-small alpha). 
if any(idx)
%
%  local variables
   Num = orders(1);
   Den = orders(2);
   Tot = Num+Den;
%
   if (length(gamma2)>1)
%
%     loop over gamma2
      for kk = find(idx)
%
%        Set the approximation interval and interpolation points
         xmax = (-log(0.01))^(1/nu(kk));   
         betaofnu = max(1,min(6,6-4.1*(nu(kk)-0.2)));  %  <-- Drumheller's original expression
         x = xmax*([1:Tot]/Tot).^betaofnu ;
%
%        Fit with polynomial coefficients $nn = [n_Num, \cdots, n_1, 1]$, $dd = [d_Den, \cdots, d_1, 1]$.
         alpha0 = 1;                               %  <-- Drumheller's choice
         B = exp(-alpha0.*x.^nu(kk)); 
         G = B - ones(size(B));
         QQ = cumprod(ones(Den,1)*x); 
         VV = ones(Den,1)*B; 
         warning off;
         temp = G/[QQ(1:Num,:); -VV.*QQ];         % ~ G*inv([QQ(1:Num,:); -VV.*QQ])
         warning on;
         nn = fliplr([1, temp(1:Num)]);
         dd = fliplr([1, temp(Num+1:Tot)]);    
%
%        Convert to partial fractions. 
         [res,pole,zilch] = residue(nn,dd);
         zero = roots(nn);
%
%        Rotate the poles as necessary. 
         bad = real(pole)>0 & imag(pole)==0; 
         if any(bad) 
            shift = pi/2; 
            newpole = [pole(bad)*exp(i*shift); pole(bad)*exp(-i*shift)];   
            newzero = pole(bad)/(2*cos(shift)-1);
            pole = [pole(~bad); newpole];
            zero = [roots(nn); newzero];
            nn = poly(zero)/prod(-zero);
            dd = poly(pole)/prod(-pole);   
            [res,pole,zilch] = residue(nn,dd);
         end
%   
%        Rotate the zeros as necessary. 
         bad = real(zero)>0 & imag(zero)==0;  
         if any(bad) 
            shift = pi/2; 
            newzero = [zero(bad)*exp(i*shift); zero(bad)*exp(-i*shift)];   
            newpole = zero(bad)/(2*cos(shift)-1);
            zero = [zero(~bad); newzero];
            pole = [roots(dd); newpole];
            nn = poly(zero)/prod(-zero);
            dd = poly(pole)/prod(-pole);   
            [res,pole,zilch] = residue(nn,dd);
         end
%
%        Use the residues and poles in the analytic formulation to generate $I(\alpha)$.
         scale = (alpha(kk)/alpha0)^(1/(2*nu(kk)));
         integral(kk) = real( sum( (res/(scale^2)) .* besselk(0, sqrt(-pole)/scale ) ) );  
%
      end
%
   else
%
%     Set the approximation interval and interpolation points
      xmax = (-log(0.01))^(1/nu);   
      betaofnu = max(1,min(6,6-4.1*(nu-0.2)));  %  <-- Drumheller's original expression
      x = xmax*([1:Tot]/Tot).^betaofnu ;
%
%     Fit with polynomial coefficients $nn = [n_Num, \cdots, n_1, 1]$, $dd = [d_Den, \cdots, d_1, 1]$.
      alpha0 = 1;                               %  <-- Drumheller's choice
      B = exp(-alpha0.*x.^nu); 
      G = B - ones(size(B));
      QQ = cumprod(ones(Den,1)*x); 
      VV = ones(Den,1)*B; 
      warning off;
      temp = G/[QQ(1:Num,:); -VV.*QQ]; 
      warning on;
      nn = fliplr([1, temp(1:Num)]);
      dd = fliplr([1, temp(Num+1:Tot)]);    
%
%     Convert to partial fractions. 
      [res,pole,zilch] = residue(nn,dd);
      zero = roots(nn);
%
%     Rotate the poles as necessary. 
      bad = real(pole)>0 & imag(pole)==0; 
      if any(bad) 
         shift = pi/2; 
         newpole = [pole(bad)*exp(i*shift); pole(bad)*exp(-i*shift)];   
         newzero = pole(bad)/(2*cos(shift)-1);
         pole = [pole(~bad); newpole];
         zero = [roots(nn); newzero];
         nn = poly(zero)/prod(-zero);
         dd = poly(pole)/prod(-pole);   
         [res,pole,zilch] = residue(nn,dd);
      end
%   
%     Rotate the zeros as necessary. 
      bad = real(zero)>0 & imag(zero)==0;  
      if any(bad) 
         shift = pi/2; 
         newzero = [zero(bad)*exp(i*shift); zero(bad)*exp(-i*shift)];   
         newpole = zero(bad)/(2*cos(shift)-1);
         zero = [zero(~bad); newzero];
         pole = [roots(dd); newpole];
         nn = poly(zero)/prod(-zero);
         dd = poly(pole)/prod(-pole);   
         [res,pole,zilch] = residue(nn,dd);
      end
%
%     Use the residues and poles in the analytic formulation to generate $I(\alpha)$ for all $\alpha$.
      scale = ones(size(res)) * (alpha(idx)/alpha0).^(1/(2*nu));
      res = res * ones(1,size(scale,2));
      pole = pole * ones(1,size(scale,2));
      integral(idx) = real( sum( (res./(scale.^2)) .* besselk(0, sqrt(-pole)./scale ) ) );  
%
   end
%
end
%
% scattering strength
ss = prefactor.*integral;
%
% convert to dB (limit to 0 max)
idx = ss > 1;
ss(idx) = 1;
idx = ss > 0;
ss(idx) = 10*log10(ss(idx));
ss(~idx) = nan;
%
