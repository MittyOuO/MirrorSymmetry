function [xValues,xWidthsM,Audit] = BuildBottomXValues( ...
        XmaxM,recvRangeM,gridI,gridIPlusM,boundaryPolicy)
%BuildBottomXValues Common bottom-grid x generator for production/audit.

[XmaxM,recvRangeM,gridI,gridIPlusM]=validateLocal( ...
    XmaxM,recvRangeM,gridI,gridIPlusM);
policy=lower(strtrim(char(string(boundaryPolicy))));

switch policy
    case 'strict_rectangular_voronoi'
        x=-XmaxM; xValues=x;
        while x < XmaxM
            next=round(x+abs((x-recvRangeM)/2)/gridI+gridIPlusM);
            if next<=x, error('G3:GridDidNotAdvance','Canonical x grid did not advance.'); end
            if next>=XmaxM
                if xValues(end)~=XmaxM, xValues(end+1)=XmaxM; end %#ok<AGROW>
                break;
            end
            xValues(end+1)=next; %#ok<AGROW>
            x=next;
        end
        xWidthsM=voronoiWidthsLocal(xValues,-XmaxM,XmaxM);

    case 'legacy_single_post_increment'
        x=-XmaxM; xValues=[];
        while x<=XmaxM
            next=round(x+abs((x-recvRangeM)/2)/gridI+gridIPlusM);
            if next<=x, error('G3:GridDidNotAdvance','Legacy x grid did not advance.'); end
            x=next; xValues(end+1)=x; %#ok<AGROW>
        end
        xWidthsM=zeros(size(xValues));
        for k=1:numel(xValues)
            if k==1, xWidthsM(k)=1; else
                xWidthsM(k)=round(abs((xValues(k)-recvRangeM)/2)/gridI+gridIPlusM);
            end
        end

    case 'legacy_channels_pre_increment'
        x=-XmaxM; xValues=[];
        while x<=XmaxM
            xValues(end+1)=x; %#ok<AGROW>
            next=round(x+abs((x-recvRangeM)/2)/gridI+gridIPlusM);
            if next<=x, error('G3:GridDidNotAdvance','Legacy channel x grid did not advance.'); end
            x=next;
        end
        xWidthsM=zeros(size(xValues));
        for k=1:numel(xValues)
            if k==1, xWidthsM(k)=1; else
                xWidthsM(k)=round(abs((xValues(k)-recvRangeM)/2)/gridI+gridIPlusM);
            end
        end

    otherwise
        error('G3:UnknownBoundaryPolicy','Unknown boundary policy: %s.',policy);
end

xValues=xValues(:).'; xWidthsM=xWidthsM(:).';
Audit=struct('BoundaryPolicy',policy,'ConfiguredXmaxM',XmaxM, ...
    'XCount',numel(xValues),'ActualMinX',min(xValues), ...
    'ActualMaxX',max(xValues),'BoundaryOvershootM', ...
    max([0,-XmaxM-min(xValues),max(xValues)-XmaxM]), ...
    'SumXWidthsM',sum(xWidthsM));
end

function widths=voronoiWidthsLocal(centers,leftBoundary,rightBoundary)
if numel(centers)==1, widths=rightBoundary-leftBoundary; return; end
edges=[leftBoundary,(centers(1:end-1)+centers(2:end))/2,rightBoundary];
widths=diff(edges);
if any(widths<=0), error('G3:InvalidVoronoiWidths','Voronoi widths must be positive.'); end
end
function [X,L,i,p]=validateLocal(X,L,i,p)
values=double([X,L,i,p]);
if any(~isfinite(values))||any(values<=0), error('G3:InvalidGridInput','Grid inputs must be finite positive scalars.'); end
X=values(1);L=values(2);i=values(3);p=values(4);
end
