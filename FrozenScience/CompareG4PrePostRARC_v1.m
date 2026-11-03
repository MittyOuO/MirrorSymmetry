function Report=CompareG4PrePostRARC_v1(Pre,Post)
arguments
    Pre (1,1) struct
    Post (1,1) struct
end
pass=isfield(Pre,'AllPass')&&isfield(Post,'AllPass')&&logical(Pre.AllPass)&&logical(Post.AllPass);
details="PRE_OR_POST_FAIL";
if pass
    a=struct2table(Pre.Rows);b=struct2table(Post.Rows);
    names=["FunctionName","ExpectedPath","ExpectedSHA256","ExpectedBytes","ResolvedPath","ResolvedSHA256","ResolvedBytes","PASS"];
    pass=height(a)==height(b)&&all(ismember(names,string(a.Properties.VariableNames)))&&all(ismember(names,string(b.Properties.VariableNames)));
    if pass
        a=sortrows(a,'FunctionName');b=sortrows(b,'FunctionName');
        pass=isequal(string(a.FunctionName),string(b.FunctionName))&& ...
            isequal(string(a.ExpectedPath),string(b.ExpectedPath))&& ...
            isequal(string(a.ExpectedSHA256),string(b.ExpectedSHA256))&& ...
            isequal(double(a.ExpectedBytes),double(b.ExpectedBytes))&& ...
            isequal(string(a.ResolvedPath),string(b.ResolvedPath))&& ...
            isequal(string(a.ResolvedSHA256),string(b.ResolvedSHA256))&& ...
            isequal(double(a.ResolvedBytes),double(b.ResolvedBytes))&&all(a.PASS)&&all(b.PASS);
    end
    details="PRE_POST_EXACT_ACTIVE_IDENTITY";
end
Report=struct('Version',"G4_PRE_POST_RARC_COMPARISON_v1",'PASS',pass,'Details',details, ...
    'PrePhase',string(Pre.Phase),'PostPhase',string(Post.Phase));
end
