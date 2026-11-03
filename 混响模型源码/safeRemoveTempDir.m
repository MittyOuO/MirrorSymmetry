function safeRemoveTempDir(TempWorkDir, OriginalDir)
% safeRemoveTempDir 安全删除临时文件夹
% 删除失败时只给出 warning，不中断主程序

try
    % 先让主进程回到原始目录，避免当前目录正在 TempWorkDir 内
    if exist('OriginalDir', 'var') && isfolder(OriginalDir)
        cd(OriginalDir);
    else
        cd(tempdir);
    end
catch
    try
        cd(tempdir);
    catch
    end
end

% 尝试让并行 worker 也离开临时目录
try
    pool = gcp('nocreate');
    if ~isempty(pool)
        pctRunOnAll cd(tempdir);
    end
catch
    % 如果 pctRunOnAll 不可用，不影响主程序
end

% 关闭可能残留的文件句柄
try
    fclose('all');
catch
end

% 给 Windows 一点释放文件锁的时间
pause(0.2);

% 尝试删除临时目录
try
    if exist(TempWorkDir, 'dir')
        rmdir(TempWorkDir, 's');
    end
catch ME
    warning('临时文件夹未能删除，但计算结果已生成。可稍后手动清理：%s\n原因：%s', ...
        TempWorkDir, ME.message);
end
end