function value = ReadJsonUtf8(fileName)
%ReadJsonUtf8 Read UTF-8 JSON and reject BOM to keep launcher behavior deterministic.
fid=fopen(fileName,'r'); if fid<0, error('ReadJsonUtf8:OpenFailed','Cannot open %s.',fileName); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes=fread(fid,inf,'*uint8').';
if numel(bytes)>=3 && isequal(bytes(1:3),uint8([239 187 191]))
    error('ReadJsonUtf8:BomNotAllowed','JSON must be UTF-8 without BOM: %s',fileName);
end
value=jsondecode(native2unicode(bytes,'UTF-8'));
end
