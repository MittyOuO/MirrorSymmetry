function Budget=EnforceG4SeedAtomicExecutionUnit_v1(TraversalCount,RandomDrawCount,Action)
% One seed permits exactly one traversal and one event-fact/random realization.
arguments
    TraversalCount (1,1) double {mustBeInteger,mustBeNonnegative}
    RandomDrawCount (1,1) double {mustBeInteger,mustBeNonnegative}
    Action (1,1) string
end
switch Action
    case "INITIALIZE"
        TraversalCount=0;RandomDrawCount=0;
    case "REGISTER_SINGLE_TRAVERSAL"
        TraversalCount=TraversalCount+1;RandomDrawCount=RandomDrawCount+1;
    case "REGISTER_TRAVERSAL"
        TraversalCount=TraversalCount+1;
    case "REGISTER_RANDOM_DRAW"
        RandomDrawCount=RandomDrawCount+1;
    case "FINALIZE"
        % Validation only.
    otherwise
        error('G4Seed1Auth:UnknownAtomicAction','Unknown SAEU action.');
end
assert(TraversalCount<=1,'G4Seed1Auth:SecondTraversalProhibited','Second traversal is prohibited.');
assert(RandomDrawCount<=1,'G4Seed1Auth:SecondRandomDrawProhibited','Second random draw is prohibited.');
Budget=struct('TraversalCount',TraversalCount,'RandomDrawCount',RandomDrawCount, ...
    'SaveEventsRerunProhibited',true,'CheckpointResumeEquivalence',"NOT_ESTABLISHED", ...
    'InterruptionPolicy',"RERUN_SAME_SEED_FROM_BEGINNING");
end
