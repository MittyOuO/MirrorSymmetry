function State=AdvanceG4ScientificAcceptance_v1(CurrentState,GatePass,GateKind,LegalSpecialOutcome)
% Atomic acceptance: legal scientific special states do not quarantine a seed.
arguments
    CurrentState (1,1) string
    GatePass (1,1) logical
    GateKind (1,1) string
    LegalSpecialOutcome (1,1) logical = false
end
assert(any(CurrentState==["GENERATED_UNACCEPTED","ACCEPTED_G4_SCIENCE","QUARANTINED_HOLD"]), ...
    'G4Seed1Auth:UnknownAcceptanceState','Unknown SAA state.');
if LegalSpecialOutcome
    State=struct('State',"GENERATED_UNACCEPTED",'G4_RESULT_COUNT',0, ...
        'GateKind',GateKind,'LegalSpecialOutcome',true);
elseif ~GatePass
    State=struct('State',"QUARANTINED_HOLD",'G4_RESULT_COUNT',0, ...
        'GateKind',GateKind,'LegalSpecialOutcome',false);
else
    if GateKind=="FINAL_ALL_REQUIRED_GATES" && CurrentState=="GENERATED_UNACCEPTED"
        next="ACCEPTED_G4_SCIENCE";
    else
        next=CurrentState;
    end
    State=struct('State',next,'G4_RESULT_COUNT',double(next=="ACCEPTED_G4_SCIENCE"), ...
        'GateKind',GateKind,'LegalSpecialOutcome',false);
end
end
