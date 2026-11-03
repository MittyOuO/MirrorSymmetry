function [Events,Access] = ReadG4PairingFieldsHDF5_v2(MatPath,Indices,MethodId)
%ReadG4PairingFieldsHDF5_v2 Exact minimum-field bounded HDF5 reader.
% Reads only the frozen 11-field G4_COMMON_EVENT_TUPLE_v1 authority.
arguments
    MatPath (1,1) string
    Indices (:,1) uint64
    MethodId (1,1) string {mustBeMember(MethodId,[ ...
        "ELEMENT_REFERENCE","BULK_SELECTED_REFERENCES","CONTIGUOUS_BLOCK_REFERENCES"])}
end
fields=["Y";"CellKey";"PathInstanceKey";"PathClass";"InterfaceType"; ...
    "DelayIn";"DelayOut";"NumBotIn";"NumTopIn";"NumBotOut";"NumTopOut"];
eventCount=uint64(7842120);
assert(isfile(MatPath),'G4GCPCAccess:MissingRawFacts','Raw facts path is missing.');
assert(~isempty(Indices)&&all(Indices>=1)&all(Indices<=eventCount), ...
    'G4GCPCAccess:IndexRange','Indices must be within the frozen 1..7,842,120 range.');
assert(numel(unique(Indices))==numel(Indices),'G4GCPCAccess:DuplicateIndex','Indices must be unique.');
if MethodId=="CONTIGUOUS_BLOCK_REFERENCES"
    assert(all(diff(double(Indices))==1),'G4GCPCAccess:NotContiguous','Contiguous method requires consecutive indices.');
end
p=System.Diagnostics.Process.GetCurrentProcess();p.Refresh();private0=double(p.PrivateMemorySize64);
cpu0=double(p.TotalProcessorTime.TotalSeconds);timer=tic;
fileId=H5F.open(char(MatPath),'H5F_ACC_RDONLY','H5P_DEFAULT');fileCleanup=onCleanup(@()H5F.close(fileId)); %#ok<NASGU>
first=cell2struct(cell(numel(fields),1),cellstr(fields),1);Events=repmat(first,numel(Indices),1);
referenceReads=0;
for f=1:numel(fields)
    datasetId=H5D.open(fileId,char("/M2Events/"+fields(f)));datasetCleanup=onCleanup(@()H5D.close(datasetId));
    switch MethodId
        case "ELEMENT_REFERENCE"
            values=cell(numel(Indices),1);
            for k=1:numel(Indices),values{k}=readOneLocal(datasetId,Indices(k));end
            referenceReads=referenceReads+numel(Indices);
        case "BULK_SELECTED_REFERENCES"
            values=readSelectedLocal(datasetId,Indices);referenceReads=referenceReads+1;
        case "CONTIGUOUS_BLOCK_REFERENCES"
            values=readContiguousLocal(datasetId,Indices(1),numel(Indices));referenceReads=referenceReads+1;
    end
    for k=1:numel(Indices),Events(k).(char(fields(f)))=values{k};end
    clear datasetCleanup
end
wall=toc(timer);p.Refresh();w=whos('Events');
Access=struct('AccessVersion','G4_PAIRING_MINIMUM_FIELD_HDF5_ACCESS_v2', ...
    'StoragePath',char(MatPath),'MethodId',char(MethodId),'FieldSet','FROZEN_11_FIELD_TUPLE', ...
    'Fields',fields,'FieldCount',numel(fields),'SubsetEventCount',numel(Indices), ...
    'DereferenceCount',numel(fields)*numel(Indices),'ReferenceArrayReadCount',referenceReads, ...
    'FirstIndex',double(min(Indices)),'LastIndex',double(max(Indices)), ...
    'WallSeconds',wall,'CPUSeconds',double(p.TotalProcessorTime.TotalSeconds)-cpu0, ...
    'PrivateBytesBefore',private0,'PrivateBytesAfter',double(p.PrivateMemorySize64), ...
    'PrivateBytesDelta',double(p.PrivateMemorySize64)-private0,'WorkingSetBytes',double(p.WorkingSet64), ...
    'PeakWorkingSetBytes',double(p.PeakWorkingSet64),'ReturnedValueBytes',w.bytes, ...
    'FullEventStructLoaded',false,'UnrelatedFieldRead',false,'ImpulseResponseCalled',false, ...
    'RandomDrawCount',0,'M2TraversalCount',0);
end

function values=readSelectedLocal(datasetId,indices)
fileSpace=H5D.get_space(datasetId);fileCleanup=onCleanup(@()H5S.close(fileSpace));
coords=[zeros(1,numel(indices));double(indices(:).'-1)];H5S.select_elements(fileSpace,'H5S_SELECT_SET',coords);
memSpace=H5S.create_simple(1,numel(indices),[]);memCleanup=onCleanup(@()H5S.close(memSpace));
refs=H5D.read(datasetId,'H5T_STD_REF_OBJ',memSpace,fileSpace,'H5P_DEFAULT');values=dereferenceLocal(datasetId,refs,numel(indices));
end

function values=readContiguousLocal(datasetId,firstIndex,count)
fileSpace=H5D.get_space(datasetId);fileCleanup=onCleanup(@()H5S.close(fileSpace));
H5S.select_hyperslab(fileSpace,'H5S_SELECT_SET',[0 double(firstIndex-1)],[],[1 count],[]);
memSpace=H5S.create_simple(1,count,[]);memCleanup=onCleanup(@()H5S.close(memSpace));
refs=H5D.read(datasetId,'H5T_STD_REF_OBJ',memSpace,fileSpace,'H5P_DEFAULT');values=dereferenceLocal(datasetId,refs,count);
end

function value=readOneLocal(datasetId,index)
fileSpace=H5D.get_space(datasetId);fileCleanup=onCleanup(@()H5S.close(fileSpace));
H5S.select_hyperslab(fileSpace,'H5S_SELECT_SET',[0 double(index-1)],[],[1 1],[]);
memSpace=H5S.create_simple(1,1,[]);memCleanup=onCleanup(@()H5S.close(memSpace));
ref=H5D.read(datasetId,'H5T_STD_REF_OBJ',memSpace,fileSpace,'H5P_DEFAULT');value=decodeReferenceLocal(datasetId,ref);
end

function values=dereferenceLocal(datasetId,refs,count)
values=cell(count,1);
for k=1:count
    if iscell(refs),ref=refs{k};else,ref=refs(:,k);end
    values{k}=decodeReferenceLocal(datasetId,ref);
end
end

function value=decodeReferenceLocal(datasetId,ref)
objectId=H5R.dereference(datasetId,'H5R_OBJECT',ref);objectCleanup=onCleanup(@()H5D.close(objectId));
raw=H5D.read(objectId);matlabClass=matlabClassLocal(objectId);
if isstruct(raw)&&isfield(raw,'real')&&isfield(raw,'imag')
    value=complex(double(raw.real),double(raw.imag));
elseif strcmp(matlabClass,'char')
    value=char(raw(:).');
elseif strcmp(matlabClass,'logical')
    value=logical(raw);
elseif isscalar(raw)
    value=raw;
else
    value=raw(:).';
end
end

function matlabClass=matlabClassLocal(objectId)
matlabClass='';
try
    attrId=H5A.open(objectId,'MATLAB_class');attrCleanup=onCleanup(@()H5A.close(attrId));
    raw=H5A.read(attrId);matlabClass=strtrim(char(raw(:).'));
catch
end
end
