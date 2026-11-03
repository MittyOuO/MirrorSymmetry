function [ms1,ms2] = ScatterFunc(r,c,CosFi,tht,miu,nn)
%SCATTERFUNC 此处显示有关此函数的摘要
%   此处显示详细说明
% 
ms1 = abs(miu*((sind(r)*sind(c))^nn));
%ms=miu*((sind(r)*sind(c))^nn);%
dertOmg = (cosd(r)^2+cosd(c)^2-2*cosd(r)*cosd(c)*CosFi)/((sind(r)+sind(c))^2);
% ∆Ω=((cosθ)^2+(cosθ)^2-2cosθcosθ'cosφ')/(sinθ+sinθ')^2
ms2 = ((1+dertOmg)^2)*exp(-dertOmg/(2*(tht^2)));
% S(θ,θ',φ')=μsinθsinθ'+ν(1+∆Ω)^2×exp-(∆Ω/2σ^2)
% 其中，σ为海底的均方根斜率 （rms slope）
%ms=miu*((sind(r)*sind(c))^nn);%
%ms=v*((1+dertOmg)^2)*exp(-dertOmg/(2*(tht^2)))-v;
end

