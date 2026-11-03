function [file,info] = WidebandBTRKernel(E,G,tx,fs,angles,P,c)
% True element travel times, fractional FIR, analytic matched filter and
% frequency-dependent steering. Overlap-add blocks are kept on disk.
timer=tic; N=G.N; nTime=ceil(P.TWindow*fs)+1;
file=[tempname '.mat']; disk=matfile(file,'Writable',true);
disk.yBTR(nTime,numel(angles))=complex(single(0));
tx=double(tx(:).'); if isempty(tx),tx=1;end
if isreal(tx) && numel(tx)>1,tx=hilbert(tx);end
L=numel(tx); energy=sum(abs(tx).^2); if energy==0,energy=1;end
actual=double(G.ElementXYZ)-double(G.CenterXYZ(:).');
if strcmpi(P.SteeringMode,'geometry_matched'),nominal=actual;
else,nominal=double(G.NominalElementXYZ)-double(G.CenterXYZ(:).');end
psi=deg2rad(G.ArrayHeadingDeg);
U=[cos(psi)*sind(angles(:).')-sin(psi)*cosd(angles(:).'); ...
   sin(psi)*sind(angles(:).')+cos(psi)*cosd(angles(:).'); zeros(1,numel(angles))];
projections=nominal*U;
halo=ceil(max(vecnorm(actual,2,2))/c*fs)+3;
steerHalo=ceil(max(abs(projections(:)))/c*fs)+3;
blockLength=8192; support=L-1+steerHalo+4;
nfft=2^nextpow2(blockLength+2*support+1);
K=abs(fft(tx,nfft)).^2/energy;
[sorted,rank]=sort(K,'descend');
keep=find(cumsum(sorted.^2)>=sum(K.^2)*(1-1e-7),1);
active=sort(rank(1:keep));
discard=true(size(K));discard(active)=false;
dropBound=sqrt(sum(K(discard).^2)/max(sum(K.^2),realmin));
f=(active-1)*fs/nfft;f(f>fs/2)=f(f>fs/2)-fs;
if N>1,step=nominal(2,:)-nominal(1,:);else,step=[0 0 0];end
uniform=max(vecnorm(nominal-(nominal(1,:)+(0:N-1).'*step),2,2))<1e-8;
nSpatial=max(64,16*2^nextpow2(N)); frequencyBlock=128;
lag=[-support:-1,0:blockLength-1+support];
fftIndex=mod(lag,nfft)+1;
peakMemory=8*N*nfft+8*N*blockLength+8*nSpatial*frequencyBlock+ ...
    16*numel(angles)*nfft+64*N*1024+16*numel(angles)*(blockLength+2*support);
[delay,order]=sort(double(E.Delay(:))); gain=E.ComplexGain(order);
xyz=[E.X(order),E.Y(order),E.Z(order)];phi=E.PhiR(order);
receiveMode='legacy_geometric';
if isfield(P,'ReceivePhaseMode'),receiveMode=lower(char(string(P.ReceivePhaseMode)));end
strictReceive=ismember(receiveMode,{'terminal_k','exact_element_delays'});
if strictReceive,receiveRecords=E.ReceivePathRecords(order);end
fprintf('Wideband BTR: %d events, %d elements, Fs=%g, FFT=%d, active bins=%d, memory estimate=%.1f MiB\n', ...
    numel(delay),N,fs,nfft,numel(active),peakMemory/2^20);
for b0=-halo:blockLength:nTime-1+halo
    if isfield(P,'CancelFlagFile') && ~isempty(P.CancelFlagFile) && isfile(P.CancelFlagFile)
        error('BTRfromEvents:Cancelled','BTR cancelled');
    end
    selected=find(delay>=(b0-halo-2)/fs & delay<=(b0+blockLength+halo+2)/fs);
    h=complex(zeros(N,blockLength,'single'));
    for e0=1:1024:numel(selected)
        ii=selected(e0:min(e0+1023,end)); q=double(xyz(ii,:));
        good=all(isfinite(q),2);
        dt=zeros(N,numel(ii));
        relativeGain=ones(N,numel(ii));
        if strictReceive
            [dt,relativeGain]=ComputeReceivePathOffsets(receiveRecords(ii),G,c,receiveMode);
        elseif any(good)
            [~,dt(:,good)]=ComputeEventArrayPhase(q(good,:),G.ElementXYZ,G.CenterXYZ,c);
        end
        if ~strictReceive && any(~good)
            direction=[cosd(phi(ii(~good))).';sind(phi(ii(~good))).';zeros(1,sum(~good))];
            dt(:,~good)=-actual*direction/c;
        end
        position=(delay(ii).'+dt)*fs-b0; base=floor(position);a=position-base;
        % Four-tap Lagrange fractional-delay FIR, no carrier phase multiplier.
        coeff={-a.*(a-1).*(a-2)/6, (a+1).*(a-1).*(a-2)/2, ...
            -(a+1).*a.*(a-2)/2, (a+1).*a.*(a-1)/6};
        for j=1:4
            column=base+j-2+1;valid=column>=1 & column<=blockLength;
            [row,~]=find(valid); amp=single(coeff{j}.*gain(ii).'.*relativeGain);
            index=row+(column(valid)-1)*N;
            added=accumarray(index(:),amp(valid),[N*blockLength,1],@sum,complex(single(0)));
            h=h+reshape(added,N,blockLength);
        end
    end
    if ~any(h(:)),continue;end
    H=fft(h,nfft,2);clear h;
    beam=complex(zeros(numel(angles),nfft,'single'));
    for k0=1:frequencyBlock:numel(active)
        kk=k0:min(k0+frequencyBlock-1,numel(active));bins=active(kk);freq=f(kk);
        if uniform && N>1
            spatial=fft(H(:,bins),nSpatial,1);
            for aScan=1:numel(angles)
                query=freq*(step*U(:,aScan))/c*nSpatial;
                base=floor(query);a=query-base;
                cw=[-a.*(a-1).*(a-2)/6; (a+1).*(a-1).*(a-2)/2; ...
                    -(a+1).*a.*(a-2)/2; (a+1).*a.*(a-1)/6];
                v=complex(zeros(1,numel(kk),'single'));
                for j=1:4
                    idx=mod(base+j-2,nSpatial)+1+(0:numel(kk)-1)*nSpatial;
                    v=v+spatial(idx).*single(cw(j,:));
                end
                beam(aScan,bins)=v.*single(exp(-2i*pi*freq*projections(1,aScan)/c).*K(bins)/N);
            end
        else
            for aScan=1:numel(angles)
                weights=single(exp(-2i*pi*(projections(:,aScan)/c)*freq));
                beam(aScan,bins)=sum(H(:,bins).*weights,1).*single(K(bins)/N);
            end
        end
    end
    clear H spatial;
    y=ifft(beam,[],2);clear beam;
    destination=b0+lag+1; inside=destination>=1 & destination<=nTime;
    dest=destination(inside);
    disk.yBTR(dest(1):dest(end),:)=disk.yBTR(dest(1):dest(end),:)+y(:,fftIndex(inside)).';
    fprintf('Wideband overlap-add: %.1f / %.1f s\n',min((b0+blockLength)/fs,P.TWindow),P.TWindow);
end
info=struct('BeamformingModel','wideband_true_time_delay_frequency_steering', ...
    'MatchedFilter','analytic_tx_conjugate_time_reverse_energy_normalized', ...
    'MatchedFilterDelayCompensationSamples',L-1,'ProcessingFs',fs, ...
    'FractionalDelay','4_tap_Lagrange_FIR','SpatialInterpolation','16x_FFT_4_tap_Lagrange', ...
    'SpectralFilterRelativeL2DiscardBound',dropBound, ...
    'BlockLength',blockLength,'FFTLength',nfft,'ActiveFrequencyBins',numel(active), ...
    'PeakWorkingMemoryEstimate',peakMemory,'ProcessingTime',toc(timer), ...
    'ReceivePhaseMode',receiveMode,'ReceiveGeometricFallback',~strictReceive, ...
    'ReceivePhaseApplication','full_analytic_delay_once_no_extra_carrier');
end
