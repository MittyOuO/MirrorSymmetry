function P = DeriveG4ActualPairingEvidenceAdapter_v1(F,V,actualForensicsSHA,actualVerdictSHA, ...
    expectedScientificRunId,expectedRecoveryExecutionId,expectedRecoveryAuthorizationId, ...
    expectedSourceEventFactsSHA,expectedForensicsSHA,expectedVerdictSHA)
%DeriveG4ActualPairingEvidenceAdapter_v1 Pure fail-closed schema adapter.
% This helper does not read files, traverse events, recompute pairing, or
% mutate either immutable recovery artifact.
arguments
    F (1,1) struct
    V (1,1) struct
    actualForensicsSHA (1,1) string
    actualVerdictSHA (1,1) string
    expectedScientificRunId (1,1) string
    expectedRecoveryExecutionId (1,1) string
    expectedRecoveryAuthorizationId (1,1) string
    expectedSourceEventFactsSHA (1,1) string
    expectedForensicsSHA (1,1) string
    expectedVerdictSHA (1,1) string
end

P=struct;
P.AdapterVersion='G4_ACTUAL_PAIRING_EVIDENCE_ADAPTER_v1';
P.PairingForensicsSHA256=char(lower(actualForensicsSHA));
P.PairingVerdictSHA256=char(lower(actualVerdictSHA));
P.ScientificRunId=char(expectedScientificRunId);
P.RecoveryExecutionId=char(expectedRecoveryExecutionId);
P.RecoveryAuthorizationId=char(expectedRecoveryAuthorizationId);
P.SourceEventFactsSHA256=char(lower(expectedSourceEventFactsSHA));

P.VerdictPASS=logicalFieldLocal(V,'PASS');
P.VerdictFullPopulation=logicalFieldLocal(V,'ActualFullPopulation');
P.VerdictExactTupleAuthority=logicalFieldLocal(V,'ExactTupleComparisonAuthoritative')&& ...
    fieldExistsLocal(V,'HashUsedAsSoleEqualityAuthority')&& ...
    ~logicalFieldLocal(V,'HashUsedAsSoleEqualityAuthority');

P.IdentityPASS=all([ ...
    stringFieldLocal(F,'ScientificRunId')==expectedScientificRunId, ...
    stringFieldLocal(V,'ScientificRunId')==expectedScientificRunId, ...
    stringFieldLocal(F,'ScientificRunId')==stringFieldLocal(V,'ScientificRunId'), ...
    stringFieldLocal(F,'RecoveryExecutionId')==expectedRecoveryExecutionId, ...
    stringFieldLocal(V,'RecoveryExecutionId')==expectedRecoveryExecutionId, ...
    stringFieldLocal(F,'RecoveryExecutionId')==stringFieldLocal(V,'RecoveryExecutionId'), ...
    stringFieldLocal(F,'AuthorizationId')==expectedRecoveryAuthorizationId, ...
    stringFieldLocal(V,'AuthorizationId')==expectedRecoveryAuthorizationId, ...
    stringFieldLocal(F,'AuthorizationId')==stringFieldLocal(V,'AuthorizationId'), ...
    lower(stringFieldLocal(F,'SourceEventFactsSHA256'))==lower(expectedSourceEventFactsSHA), ...
    lower(stringFieldLocal(V,'SourceEventFactsSHA256'))==lower(expectedSourceEventFactsSHA), ...
    lower(stringFieldLocal(F,'SourceEventFactsSHA256'))==lower(stringFieldLocal(V,'SourceEventFactsSHA256'))]);

P.VerdictSHABindingPASS=shaEqualLocal(actualVerdictSHA,stringFieldLocal(F,'PairingVerdictSHA256'))&& ...
    shaEqualLocal(actualVerdictSHA,expectedVerdictSHA);
P.ForensicsSHABindingPASS=shaEqualLocal(actualForensicsSHA,expectedForensicsSHA);
P.TupleIdentityPASS=numericFieldLocal(F,'CanonicalFieldCount')==11&& ...
    stringFieldLocal(F,'CanonicalTupleVersion')==stringFieldLocal(V,'TupleVersion')&& ...
    stringFieldLocal(F,'CanonicalTupleVersion')=="G4_COMMON_EVENT_TUPLE_v1";

P.ExpectedPlusSourceCount=numericFieldLocal(F,'ExpectedPlusSourceCount');
P.ActualPlusSourceCount=numericFieldLocal(F,'ActualPlusSourceCount');
P.N_missing_plus=numericFieldLocal(F,'N_missing_plus');
P.N_duplicate_plus=numericFieldLocal(F,'N_duplicate_plus');
P.PlusCountsPASS=isfinite(P.ExpectedPlusSourceCount)&&P.ExpectedPlusSourceCount>=0&& ...
    P.ExpectedPlusSourceCount==P.ActualPlusSourceCount&& ...
    P.N_missing_plus==0&&P.N_duplicate_plus==0;

P.ExpectedAxisSourceCount=numericFieldLocal(F,'ExpectedAxisSourceCount');
P.ActualAxisSourceCount=numericFieldLocal(F,'ActualAxisSourceCount');
P.N_missing_axis=numericFieldLocal(F,'N_missing_axis');
P.N_duplicate_axis=numericFieldLocal(F,'N_duplicate_axis');
P.AxisCountedOnce=logicalFieldLocal(F,'AxisCountedOnce');
P.AxisCountsPASS=isfinite(P.ExpectedAxisSourceCount)&&P.ExpectedAxisSourceCount>=0&& ...
    P.ExpectedAxisSourceCount==P.ActualAxisSourceCount&& ...
    P.N_missing_axis==0&&P.N_duplicate_axis==0&&P.AxisCountedOnce;

P.NoEqualCountSubstitution=logicalFieldLocal(F,'NoEqualCountSubstitution');
P.NoSubstitutionPASS=fieldExistsLocal(F,'NoEqualCountSubstitution')&&P.NoEqualCountSubstitution;
P.InvalidGroups=numericFieldLocal(F,'InvalidGroups');
P.InvalidGroupsPASS=isfinite(P.InvalidGroups)&&P.InvalidGroups==0;
P.SupportingEvidenceLabelConsistency=stringFieldLocal(F,'Evidence6')=="ACTUAL_PASS_CANDIDATE"&& ...
    stringFieldLocal(F,'Evidence7')=="ACTUAL_PASS_CANDIDATE";

components=[P.VerdictPASS P.VerdictFullPopulation P.VerdictExactTupleAuthority ...
    P.IdentityPASS P.VerdictSHABindingPASS P.ForensicsSHABindingPASS ...
    P.TupleIdentityPASS P.PlusCountsPASS P.AxisCountsPASS ...
    P.NoSubstitutionPASS P.InvalidGroupsPASS];
P.PASS=all(components);
names=["VerdictPASS","VerdictFullPopulation","VerdictExactTupleAuthority", ...
    "IdentityPASS","VerdictSHABindingPASS","ForensicsSHABindingPASS", ...
    "TupleIdentityPASS","PlusCountsPASS","AxisCountsPASS", ...
    "NoSubstitutionPASS","InvalidGroupsPASS"];
P.FailedComponents=cellstr(names(~components));
P.PairingRecomputed=false;
P.RawEventFactsRead=false;
P.ImmutableArtifactsMutated=false;
P.CreatedUTC=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
end

function tf=fieldExistsLocal(S,name)
tf=isfield(S,name);
end

function tf=logicalFieldLocal(S,name)
tf=false;
if isfield(S,name)
    x=S.(name);
    tf=(islogical(x)||isnumeric(x))&&isscalar(x)&&isfinite(double(x))&&logical(x);
end
end

function x=numericFieldLocal(S,name)
x=NaN;
if isfield(S,name)
    value=S.(name);
    if isnumeric(value)&&isscalar(value),x=double(value);end
end
end

function x=stringFieldLocal(S,name)
x="";
if isfield(S,name)
    value=string(S.(name));
    if isscalar(value),x=value;end
end
end

function tf=shaEqualLocal(a,b)
a=lower(string(a));b=lower(string(b));
tf=isscalar(a)&&isscalar(b)&&strlength(a)==64&&strlength(b)==64&& ...
    ~isempty(regexp(char(a),'^[0-9a-f]{64}$','once'))&& ...
    ~isempty(regexp(char(b),'^[0-9a-f]{64}$','once'))&&a==b;
end
