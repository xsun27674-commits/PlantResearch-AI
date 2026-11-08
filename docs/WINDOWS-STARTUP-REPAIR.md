# Windows 启动修复与诊断

## 已安装用户：不重装，不动科研数据

1. 从本修复PR的开发分支点击 **Code → Download ZIP**，将源码完整解压。
2. 关闭旧的 PlantResearch AI 启动器窗口。
3. 在源码根目录双击 **Repair-Startup.cmd**，阅读确认框并确认。
4. 用原来的桌面快捷方式重新启动。

此修复只更新 `%LOCALAPPDATA%\PlantResearchAI` 中的 `Launcher.ps1`、`ServiceProcess.cs` 和 `app\backend\bootstrap.py`。旧文件备份在 `startup-backups` 下，已有运行环境、依赖、数据库和 `data` 目录均不改动。不下载软件，不需要管理员权限，不修改PATH/注册表，不重新打包或发布安装器。默认安装目录不存在时会停止；不要用重新安装替代诊断。

## 已确定的代码问题

旧健康检查向 `$home` 赋值。PowerShell变量不区分大小写，`$HOME`是只读变量；此赋值会抛异常，而旧代码的空catch吞掉了异常，健康检查因此永远无法成功。此问题能解释按钮灰色/就绪失败，**不能单独解释Python为什么未监听8000端口**。

旧启动器没有记录PID、退出码、工作目录、具体命令和每次HTTP失败原因，Python也没有独立的导入进度日志，因此空的backend日志不能证明后端没有启动，也无法区分原生依赖崩溃、导入阻塞、解释器初始化失败或输出捕获问题。本次改为.NET进程对象及.NET异步回调直接写入自动刷新日志，不再依赖Start-Process的PowerShell重定向生命周期，也不在后台回调中运行PowerShell脚本块。未断言旧重定向是该Windows实例的唯一根因。

## 新启动流程

- 验证安装中的Python、标准库encodings、Node、后端文件和前端BUILD_ID，路径缺失直接给出提示。
- 为每次启动创建独立日志子目录，不覆盖旧诊断。
- 使用绝对解释器/脚本路径和明确工作目录，通过`-u -X faulthandler`启动Python。
- 仅在子进程中移除可能干扰便携Python的PYTHONHOME/PYTHONPATH；不改系统环境。不记录模型密钥或完整环境变量。
- Python入口立即输出PID、版本、位数、解释器和工作目录。逐项记录依赖导入前后检查点，再导入应用、运行uvicorn。
- 在`127.0.0.1:8000/api/health`健康后才启动前端；再检查3000的首页和代理健康接口。
- 后端/前端启动分别最多等待120秒；提前退出立即显示服务名、退出码，超时保留最近HTTP失败原因。
- 失败弹窗指出诊断路径，停止本启动器创建的服务，恢复启动按钮；不结束其他应用。
- 浏览器无法自动打开只记录提示，已健康的服务不会因此被停止。

## 查看诊断

点击 **Open logs**，打开最新时间戳文件夹：

| 文件 | 内容 |
|---|---|
| launcher.log | 实际命令、工作目录、可执行路径、PID和失败原因 |
| backend.out.log / backend.err.log | .NET捕获的Python输出、错误和原生故障信息 |
| python-startup.log | 独立文件输出的导入检查点及Python traceback |
| frontend.out.log / frontend.err.log | 前端进程输出 |

Launcher辅助代码加载失败则写入 `logs\launcher-initialization.log` 并弹窗。若Python在执行bootstrap前就失败，python-startup.log可能不存在，此时查看backend.err.log与launcher.log中的退出码。若Python仍运行但导入卡住，python-startup.log最后一条Importing记录可定位阶段。请保留完整日志，不要盲目重装或结束未知进程。日志可能含本机用户名路径，不会自动上传；分享前可遮盖路径中的用户名，不要附上密钥或科研数据。

## 验证范围

当前Linux执行：

- `python -m pytest backend/test_app.py backend/test_bootstrap.py -q`：8项通过，包含从无关工作目录真实启动健康接口、缺失依赖失败的stdout/stderr及独立traceback日志、仅导入检查不启动服务。
- PowerShell 7测试 `packaging/windows/tests/Test-ServiceProcess.ps1 -Python <python路径>`：实际进程的stdout、stderr、退出码、含空格路径、子进程环境，以及执行bootstrap前的解释器失败均捕获成功。
- PowerShell 7测试 `packaging/windows/tests/Test-LauncherState.ps1`：执行实际状态检查函数，通过后端先行、HOME回归、提前退出及超时原因测试；GUI控件和网络请求使用替身。
- 修改的PowerShell脚本语法检查；C#日志辅助类型实际编译、实际启动子进程。

**尚未验证：Windows PowerShell 5.1、Windows Forms实际窗口、Windows路径与原生Python扩展、Job Object子进程清理、实际修复按钮流程，以及用户机器的启动。Linux测试不等于Windows验收。** 没有使用真实模型API、付费操作或公网部署。
