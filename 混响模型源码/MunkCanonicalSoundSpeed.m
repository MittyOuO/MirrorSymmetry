function c = MunkCanonicalSoundSpeed(z, zc)
%MunkCanonicalSoundSpeed Canonical Munk deep-water profile.
z = double(z);
if nargin < 2 || isempty(zc), zc = 1300; end
validateattributes(zc, {'numeric'}, {'scalar','real','finite','nonnegative'});
c0 = 1500; epsilon = 0.00737; B = 1300;
eta = 2*(z-zc)/B;
c = c0 .* (1 + epsilon .* (eta - 1 + exp(-eta)));
end
