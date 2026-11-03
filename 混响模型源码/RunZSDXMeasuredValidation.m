%% RunZSDXMeasuredValidation 入口
% 正式验证脚本及配套数据位于 build\SYSU。保留本入口是为了避免误运行
% Re 根目录中过去的旧版验证流程。
rootDir = fileparts(mfilename('fullpath'));
validationScript = fullfile(rootDir, 'build', 'SYSU', 'RunZSDXMeasuredValidation.m');
assert(isfile(validationScript), '找不到验证脚本：%s', validationScript);
run(validationScript);
