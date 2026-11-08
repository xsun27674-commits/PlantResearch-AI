# 在 Windows 电脑运行 PlantResearch AI

## 当前云端预览诊断

云端前端仍监听127.0.0.1:3000，后端仍监听127.0.0.1:8000；首页HTTP 200，前端代理健康接口返回status=ok。服务没有停止。

这些地址属于云机器，不能在你的Windows浏览器直接访问。当前Codex会话没有提供预览映射/端口转发工具，也没有提供共享桌面控制或打开工具，因此未能核验或修复你点击的预览映射，无法提供已验证的云端预览URL。没有将未认证的科研平台暴露到公网，也没有建立第三方隧道。源码包可用于下述本地运行。

## 1. 准备软件

- Windows 10/11 64位。
- 从 https://www.python.org/downloads/ 安装 **Python 3.12 64位**，保留Python Launcher（py），勾选Add Python to PATH。
- 从 https://nodejs.org/ 安装 **Node.js 24 LTS**（包含npm）。
- 重新打开PowerShell，检查：

```powershell
py -3.12 --version
node --version
npm.cmd --version
```

压缩包包含完整项目源码、依赖锁定文件、文档和安装脚本。不含Linux虚拟环境、node_modules、构建缓存、API密钥及用户科研数据；首次安装需要联网下载依赖。

## 2. 解压与安装

将PlantResearch-AI.zip解压，例如得到：`C:\PlantResearch-AI`（该目录下应直接能看到README.md、backend、frontend、scripts）。在此目录右键“在终端中打开”，运行：

```powershell
Set-Location C:\PlantResearch-AI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
```

Bypass仅对这个启动的PowerShell进程生效，不修改系统执行策略。遇到组织策略限制时不要更改策略，使用下面的手动命令。

## 3. 启动

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-windows.ps1
```

等出现Next.js Ready后，在**这台Windows电脑**的浏览器打开：

**http://localhost:3000**

此时网站确实运行在你的Windows电脑，而不是云容器。保持终端打开；Ctrl+C停止。前后端端口被占用时脚本会报错，不会自动结束其他程序。

## 4. 手动启动（备用）

安装，均在项目根目录运行，无需激活虚拟环境：

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
npm.cmd ci --prefix frontend
```

终端A启动后端：

```powershell
.\.venv\Scripts\python.exe -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
```

终端B进入同一项目根目录，启动前端：

```powershell
npm.cmd run dev --prefix frontend
```

前端应显示3000端口；如果自动切到3001，请先检查哪个程序占用了3000端口。后端代理固定为8000，不要只改后端端口。

## 5. 验证

```powershell
Invoke-RestMethod http://localhost:3000/api/health
.\.venv\Scripts\python.exe -m pytest backend/test_app.py -q
npm.cmd run build --prefix frontend
```

预期健康接口status=ok。上传一个文本PDF和一个Excel，查看预览，选择数值列生成图表，然后下载Excel/PNG。测试和生产构建应在停止开发服务后运行，避免同时写构建目录。

## 6. 模型配置（可选）

不配置密钥也能提取PDF、统计数据、绘图、导出。在运行启动脚本的同一个PowerShell窗口设置：

```powershell
$env:DEEPSEEK_API_KEY = '在这里填入你自己的密钥'
# 或 $env:QWEN_API_KEY = '在这里填入你自己的密钥'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-windows.ps1
```

不要将真实密钥保存到项目文件或发到聊天。中国大陆网络可以优先尝试Qwen；真实API仍需账号、额度及对应服务的网络访问权限。

## 常见故障

- `py`不存在：重装Python并启用Launcher，或把命令中的`py -3.12`换成确认版本为3.12的`python`。
- `npm.ps1`执行被阻止：这里所有命令使用`npm.cmd`，不需要改系统策略。
- 安装超时：检查能否访问pypi.org、files.pythonhosted.org、registry.npmjs.org；不要关闭TLS验证。
- 端口占用：`Get-NetTCPConnection -LocalPort 3000,8000 -State Listen`，按OwningProcess在任务管理器确认程序；不要盲目结束未知进程。
- PDF无文本：扫描PDF不支持OCR。
- 中文图表字体显示方块：当前Matplotlib默认字体可能不含中文，临时用英文列名；网页中文界面不受影响。

此环境是Linux，Windows启动脚本已提供但无法在真实Windows机器执行验证。Python依赖锁定来自Linux环境；若某个依赖在Windows缺少兼容发行包，请保留完整错误信息进一步诊断，不要任意关闭验证或修改锁文件。
