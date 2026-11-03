function Report=ValidateG4Seed1RetentionManifest_v1(T,RunIdentity)
% Enforce all 12 retained classes and exact object/run identity before acceptance.
arguments
    T table
    RunIdentity (1,1) struct
end
classes=["SeedIdentity";"EventFacts";"RawHTotal";"RawHPositiveNegativeAxis"; ...
    "ObservedResponses";"ReconstructedM0C";"ScalarQoITable";"SideMetrics"; ...
    "NormalizedEnvelopeVectors";"v_model";"GateLog";"RuntimePathSHAProvenance"];
required=["ObjectClass","ObjectPath","ObjectBytes","ObjectSHA256","ScientificRunId", ...
    "RosterIndex","Seed","CreationUTC","AcceptanceState"];
fail=strings(0,1);
if ~all(ismember(required,string(T.Properties.VariableNames)))
    fail(end+1)="RETENTION_COLUMNS_MISSING";
else
    if height(T)~=12||numel(unique(string(T.ObjectClass)))~=12||~isequal(sort(string(T.ObjectClass)),sort(classes)),fail(end+1)="RETENTION_CLASS_INCOMPLETE";end
    for k=1:height(T)
        p=string(T.ObjectPath(k));
        if ~isfile(p),fail(end+1)="RETENTION_OBJECT_MISSING";continue,end
        d=dir(p);h=sha256FileLocal(p);
        if d.bytes~=double(T.ObjectBytes(k))||~strcmpi(h,string(T.ObjectSHA256(k))),fail(end+1)="RETENTION_OBJECT_SHA_MISMATCH";end
        if string(T.ScientificRunId(k))~=string(RunIdentity.ScientificRunId)||double(T.RosterIndex(k))~=1||double(T.Seed(k))~=double(RunIdentity.Seed),fail(end+1)="RETENTION_RUN_IDENTITY_MISMATCH";end
        if string(T.AcceptanceState(k))~="GENERATED_UNACCEPTED",fail(end+1)="RETENTION_STATE_INVALID";end
    end
end
Report=struct('Version',"G4_SEED1_RETENTION_ENFORCEMENT_v1",'AllPass',isempty(fail), ...
    'FailureIdentifiers',unique(fail,'stable'),'RequiredClassCount',12,'ObservedClassCount',height(T));
end
function h=sha256FileLocal(path)
fid=fopen(path,'rb');assert(fid>0);c=onCleanup(@()fclose(fid));b=fread(fid,Inf,'*uint8');md=java.security.MessageDigest.getInstance('SHA-256');d=typecast(md.digest(b),'uint8');h=string(lower(reshape(dec2hex(d,2).',1,[]))); %#ok<NASGU>
end
