function Report=ValidateG4NativeMetricPipeline_v1(T,DnumSourcePath,ExpectedDnumSHA256)
% Validate exact 10-QoI roster/classes/domains and the frozen Dnum authority.
arguments
    T table
    DnumSourcePath (1,1) string
    ExpectedDnumSHA256 (1,1) string
end
expectedQoI=["WindowEnergy";"MeanRL";"P50RL";"P95RL";"t50";"t90"; ...
    "Peak prominence";"Fixed-neighborhood peak energy";"Major-peak timing";"Major-peak amplitude"];
expectedClass=["POSITIVE_RELATIVE_LINEAR";"DB_NATIVE";"DB_NATIVE";"DB_NATIVE";"TIMING_NATIVE";"TIMING_NATIVE"; ...
    "POSITIVE_RELATIVE_LINEAR";"POSITIVE_RELATIVE_LINEAR";"TIMING_NATIVE";"POSITIVE_RELATIVE_LINEAR"];
required=["QoI","MetricClass","MCTClass","Q_M0C","Q_M2","StructuralPrerequisite"];
fail=strings(0,1);details=strings(0,1);
if ~all(ismember(required,string(T.Properties.VariableNames)))
    fail(end+1)="G4Seed1Metric:MissingColumns";details(end+1)="required metric columns missing";
end
if isempty(fail)
    q=string(T.QoI);c=string(T.MetricClass);
    if height(T)~=10||numel(unique(q))~=height(T),fail(end+1)="G4Seed1Metric:MissingOrDuplicateQoI";details(end+1)="QoI count/uniqueness mismatch";end
    if height(T)==10&&~isequal(q,expectedQoI),fail(end+1)="G4Seed1Metric:QoIRosterMismatch";details(end+1)="exact ordered QoI roster mismatch";end
    if height(T)==10&&~isequal(c,expectedClass),fail(end+1)="G4Seed1Metric:WrongMetricClass";details(end+1)="metric class mismatch";end
    if height(T)==10&&~isequal(string(T.MCTClass),expectedClass),fail(end+1)="G4Seed1Metric:WrongMCTClass";details(end+1)="MCT class mismatch";end
end
if ~isfile(DnumSourcePath)
    fail(end+1)="G4Seed1Metric:DnumMissing";details(end+1)="Dnum source missing";D=table();dsha="";
else
    dsha=sha256FileLocal(DnumSourcePath);
    if ~strcmpi(dsha,ExpectedDnumSHA256),fail(end+1)="G4Seed1Metric:DnumSHAMismatch";details(end+1)="Dnum SHA mismatch";end
    D=readtable(DnumSourcePath,'FileType','text','Delimiter',',','TextType','string','VariableNamingRule','preserve','Encoding','UTF-8');
    if height(D)~=10||~all(ismember(["QoI","MetricClass","D_num"],string(D.Properties.VariableNames)))
        fail(end+1)="G4Seed1Metric:DnumSchemaMismatch";details(end+1)="Dnum schema mismatch";
    elseif ~isequal(string(D.QoI),expectedQoI)
        fail(end+1)="G4Seed1Metric:WrongDnumRow";details(end+1)="Dnum QoI rows mismatch";
    end
end
rowState=repmat("NOT_EVALUATED",height(T),1);
if isempty(fail)
    dclass=normalizeDnumClassLocal(string(D.MetricClass));
    if ~isequal(dclass,expectedClass)
        fail(end+1)="G4Seed1Metric:WrongDnumClass";details(end+1)="Dnum metric class mismatch";
    end
    dv=double(D.D_num);
    if any(~isfinite(dv)|dv<=0),fail(end+1)="G4Seed1Metric:InvalidDnum";details(end+1)="Dnum nonfinite/nonpositive";end
    for k=1:height(T)
        q0=double(T.Q_M0C(k));q2=double(T.Q_M2(k));cls=string(T.MetricClass(k));sp=logical(T.StructuralPrerequisite(k));
        if ~isfinite(q2)
            fail(end+1)="G4Seed1Metric:NativeNonfinite";details(end+1)=T.QoI(k)+": Q_M2 nonfinite";rowState(k)="FAIL";
        elseif cls=="POSITIVE_RELATIVE_LINEAR"
            if q2<0||(isfinite(q0)&&q0<0)
                fail(end+1)="G4Seed1Metric:NativeDomainInvalid";details(end+1)=T.QoI(k)+": negative positive-domain metric";rowState(k)="FAIL";
            elseif ~isfinite(q0)||q0==0||~sp
                rowState(k)="LEGAL_D1_INVALID";
            else
                rowState(k)="VALID";
            end
        elseif cls=="TIMING_NATIVE"
            if ~isfinite(q0)||q0<0||q0>=60||q2<0||q2>=60||~sp
                fail(end+1)="G4Seed1Metric:NativeDomainInvalid";details(end+1)=T.QoI(k)+": invalid timing domain";rowState(k)="FAIL";
            else,rowState(k)="VALID";end
        elseif cls=="DB_NATIVE"
            if ~isfinite(q0)||~sp
                fail(end+1)="G4Seed1Metric:NativeNonfinite";details(end+1)=T.QoI(k)+": invalid dB native value";rowState(k)="FAIL";
            else,rowState(k)="VALID";end
        end
    end
end
Report=struct('Version',"G4_NATIVE_METRIC_PIPELINE_VALIDATOR_v1",'AllPass',isempty(fail), ...
    'FailureIdentifiers',fail,'Details',details,'RowState',rowState,'QoICount',height(T), ...
    'DnumSourcePath',DnumSourcePath,'DnumSHA256',dsha,'ExpectedDnumSHA256',ExpectedDnumSHA256, ...
    'ExactQoIRoster',expectedQoI,'ExactMetricClasses',expectedClass);
end
function out=normalizeDnumClassLocal(x)
out=strings(size(x));out(x=="positive relative-linear")="POSITIVE_RELATIVE_LINEAR";
out(x=="dB-native additive")="DB_NATIVE";out(x=="timing-native seconds additive")="TIMING_NATIVE";
end
function h=sha256FileLocal(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
