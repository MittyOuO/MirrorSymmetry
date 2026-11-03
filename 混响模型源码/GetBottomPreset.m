function preset = GetBottomPreset(typeName)
%GetBottomPreset Resolve the bilingual sediment preset library.
key = lower(strtrim(string(typeName)));
switch key
    case {"south_china_sea_silt","南海粉砂质"}, values = [1560 1.80 0.05]; key = "south_china_sea_silt";
    case {"theoretical_clay","理论黏土质"}, values = [1500 1.60 0.50]; key = "theoretical_clay";
    case {"high_water_content_soft_mud","高含水软泥/极软黏土"}, values = [1455 1.53 0.02]; key = "high_water_content_soft_mud";
    case {"typical_soft_clay","典型黏土质软底"}, values = [1476 1.66 0.04]; key = "typical_soft_clay";
    case {"dense_clay","较密实黏土质底"}, values = [1508 1.77 0.06]; key = "dense_clay";
    case {"apl_silty_clay","apl 等效粉质黏土"}, values = [1474 1.17 0.09]; key = "apl_silty_clay";
    case {"apl_sandy_clay","apl 等效砂质黏土"}, values = [1527 1.38 0.13]; key = "apl_sandy_clay";
    case {"slightly_positive_speed_clay","轻度正声速差黏土质底"}, values = [1530 1.70 0.13]; key = "slightly_positive_speed_clay";
    case {"dense_clay_silt_mix","密实黏土—粉砂混合底","密实黏土-粉砂混合底"}, values = [1575 1.80 0.08]; key = "dense_clay_silt_mix";
    case {"compacted_clay","压实黏土"}, values = [1620 1.90 0.25]; key = "compacted_clay";
    case {"indian_ocean_silt","印度洋粉砂质"}, values = [1580 2.05 0.30]; key = "indian_ocean_silt";
    case {"fine_sand","细砂质"}, values = [1650 1.90 0.25]; key = "fine_sand";
    case {"gravel","砂砾质"}, values = [1800 2.10 0.20]; key = "gravel";
    otherwise
        error('GetBottomPreset:UnknownType', 'Unknown Bottom.type: %s', typeName);
end
preset = struct('type',char(key),'Cb',values(1),'Rhob',values(2),'Alphab',values(3));
end
