function [Row,Audit] = BuildBottomGridRow(xLocal,xWidthM,YmaxM,recvRangeM, ...
        gridI,gridIPlusM,totalRangeLimitM,boundaryPolicy)
%BuildBottomGridRow Generate one signed-y bottom row and audit metadata.

vals=double([xLocal,xWidthM,YmaxM,recvRangeM,gridI,gridIPlusM,totalRangeLimitM]);
if any(~isfinite(vals)) || xWidthM<=0 || YmaxM<=0 || recvRangeM<=0 || ...
        gridI<=0 || gridIPlusM<=0 || totalRangeLimitM<=0
    error('G3:InvalidGridRowInput','Invalid bottom-grid row input.');
end
policy=lower(strtrim(char(string(boundaryPolicy))));

yAbs=0; breadths=1;
switch policy
    case 'strict_rectangular_voronoi'
        while yAbs(end)<YmaxM
            next=round(yAbs(end)+abs(yAbs(end)+(xLocal-recvRangeM)/2)/gridI+gridIPlusM);
            if next<=yAbs(end), error('G3:GridDidNotAdvance','Canonical y grid did not advance.'); end
            if next>=YmaxM
                if yAbs(end)~=YmaxM, yAbs(end+1)=YmaxM; end %#ok<AGROW>
                break;
            end
            yAbs(end+1)=next; %#ok<AGROW>
        end
        breadths=positiveVoronoiWidthsLocal(yAbs,YmaxM);

    case {'legacy_single_post_increment','legacy_channels_pre_increment'}
        yAbs=0; breadths=1; y=0; breadth=1;
        while true
            next=round(y+abs(y+(xLocal-recvRangeM)/2)/gridI+gridIPlusM);
            if next<=y, error('G3:GridDidNotAdvance','Legacy y grid did not advance.'); end
            if next>YmaxM, break; end
            breadth=round(abs(y+(xLocal-recvRangeM)/2)/gridI+gridIPlusM);
            y=next; yAbs(end+1)=y; breadths(end+1)=breadth; %#ok<AGROW>
        end

    otherwise
        error('G3:UnknownBoundaryPolicy','Unknown boundary policy: %s.',policy);
end

nSigned=1+2*(numel(yAbs)-1);
X=repmat(xLocal,nSigned,1); Y=zeros(nSigned,1); YAbs=zeros(nSigned,1);
Side=zeros(nSigned,1); XWidth=repmat(xWidthM,nSigned,1); YWidth=zeros(nSigned,1);
PairId=zeros(nSigned,1); cursor=1;
YWidth(1)=breadths(1); PairId(1)=1;
for k=2:numel(yAbs)
    Y(cursor+1)=yAbs(k); Y(cursor+2)=-yAbs(k);
    YAbs(cursor+1:cursor+2)=yAbs(k); Side(cursor+1)=1; Side(cursor+2)=-1;
    YWidth(cursor+1:cursor+2)=breadths(k); PairId(cursor+1:cursor+2)=k;
    cursor=cursor+2;
end
CellArea=XWidth.*YWidth;
SourceRange=hypot(X,Y);
ReceiverRange=hypot(X-recvRangeM,Y);
TotalRange=SourceRange+ReceiverRange;
Within=TotalRange<=totalRangeLimitM;

Row=struct('X',X,'Y',Y,'YAbs',YAbs,'Side',Side,'XWidthM',XWidth, ...
    'YWidthM',YWidth,'CellArea',CellArea,'SourceRadialRangeM',SourceRange, ...
    'ReceiverRadialRangeM',ReceiverRange,'TotalTwoLegRangeM',TotalRange, ...
    'Within80kmMask',Within,'IsAxis',Y==0,'MirrorPairId',PairId);
firstFail=find(~Within,1,'first');
Audit=struct('BoundaryPolicy',policy,'CandidateCellCount',nSigned, ...
    'AxisFacetCount',sum(Y==0),'PlusCount',sum(Y>0),'MinusCount',sum(Y<0), ...
    'PlusArea',sum(CellArea(Y>0)),'MinusArea',sum(CellArea(Y<0)), ...
    'TotalArea',sum(CellArea),'ActualMinY',min(Y),'ActualMaxY',max(Y), ...
    'ActualMaxSourceRadialRange',max(SourceRange), ...
    'ActualMaxReceiverRadialRange',max(ReceiverRange), ...
    'CutoffTriggered',any(~Within),'CutoffExcludedCandidateCellCount',sum(~Within), ...
    'FirstCutoffYAbs',NaN);
if ~isempty(firstFail), Audit.FirstCutoffYAbs=YAbs(firstFail); end
end

function widths=positiveVoronoiWidthsLocal(yAbs,YmaxM)
if numel(yAbs)==1, widths=2*YmaxM; return; end
widths=zeros(size(yAbs));
widths(1)=yAbs(2);
for k=2:numel(yAbs)-1
    widths(k)=(yAbs(k+1)-yAbs(k-1))/2;
end
widths(end)=YmaxM-(yAbs(end-1)+yAbs(end))/2;
if any(widths<=0), error('G3:InvalidVoronoiWidths','Signed-y Voronoi widths must be positive.'); end
end
