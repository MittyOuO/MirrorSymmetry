function F = BuildCanonicalFormalBandpass(Fs)
% Release-external audit helper. The ZPK is the authority.
arguments
    Fs (1,1) double {mustBeFinite,mustBePositive}
end
f0=1000; fL=f0/2^(1/6); fH=f0*2^(1/6); n=4;
Wn=[fL fH]/(Fs/2);
[z,p,k]=butter(n,Wn,'bandpass');
[sos,gSOS]=zp2sos(z,p,k);
[B,A,gCTF]=zp2ctf(z,p,k);
[b,a]=butter(n,Wn,'bandpass'); % Exact historical direct-form construction; diagnostic only.
F=struct('FsHz',Fs,'FilterFamily','Butterworth','PrototypeOrderN',n, ...
    'OnePassBandpassOrder',2*n,'ZeroPhaseEffectiveOrder',4*n, ...
    'CenterHz',f0,'LowerHz',fL,'UpperHz',fH,'Wn',Wn, ...
    'z',z,'p',p,'k',k,'sos',sos,'gSOS',gSOS, ...
    'B',B,'A',A,'gCTF',gCTF,'b',b,'a',a);
end
