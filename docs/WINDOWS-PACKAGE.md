# Windows一键离线包（预发布）

## 用户入口

下载 `PlantResearch-AI-Windows-x64.zip`，全部解压后双击 `Install.cmd`。
它调用同目录可审阅的Install.ps1，在确认后仅解压至当前用户LocalAppData并创建桌面快捷方式。无需管理员权限、单独安装Python/Node或手动命令。

完整源码、Python 3.12.10（Python官方NuGet便携发行版）、Node.js 24.14.0官方Windows x64 ZIP、预安装Windows Python wheels、Windows npm依赖和Next生产构建均在payload.zip内。

`packaging/windows/requirements.txt`选择有已发布Windows二进制包的版本，与云端依赖单独锁定，后续更新需重新验证。Python发行包通过官方NuGet catalog SHA512核验；Node通过官方SHASUMS256核验。pip通过PyPI TLS和包哈希获取wheels，npm ci通过package-lock integrity校验。payload.sha256用于安装前检查压缩包完整性，不等同代码签名。

## 启动与关闭

桌面快捷方式打开Windows Forms启动器，自动启动仅监听loopback的FastAPI与Next生产服务。通过首页及代理健康接口后打开浏览器。使用Windows Job Object的KILL_ON_JOB_CLOSE控制本次启动的进程树，关闭启动器释放句柄。端口冲突只报错，不杀其他软件；单实例mutex避免重复启动。数据位于安装根目录data，日志位于logs。关闭浏览器不会停止后台服务，需关闭启动器。

可在启动器输入DeepSeek或Qwen密钥并重新启动服务。通过临时的进程级环境传给后端，立即恢复父进程环境，不写用户/系统环境变量或配置文件。密钥仍会存在启动器及后端内存中，此设计不防御同用户进程内存读取。

## 安全审查

- 不需要UAC或管理员权限，无注册表、PATH、系统服务、开机自启、防火墙修改。
- 不使用下载即执行脚本；最终包基础安装完全离线，不新增第三方隧道。
- PowerShell Bypass仅限快捷方式和安装脚本启动的进程，不永久更改ExecutionPolicy。
- 安装前明确询问是否写用户目录及创建快捷方式。已存在安装目录时拒绝覆盖，不删除已有科研数据。
- 桌面快捷方式名称若已存在，安装器拒绝覆盖。
- 初始包不含上传数据、真实密钥、Git凭据、Linux虚拟环境或Linux原生依赖。
- 窗口仅限可信本地单用户；没有公共站点认证、权限与隔离，原版限制仍然适用。
- 无Authenticode数字签名和原生exe安装器；组织策略可能限制脚本，不能要求用户关闭安全软件来绕过。
- 不提供自动更新；这是预发布安装包，依赖漏洞审查与许可证合规发布仍需独立维护。

## 验证范围

已检查Windows运行时PE文件、Windows x64依赖选择、Python与Node发行包校验和、npm完整性、payload文件清单及ZIP完整性。使用与Windows相同的Python顶层依赖版本在Linux安装并运行应用集成测试；前端生产构建成功。

未验证：真实Windows上的安装、快捷方式、Windows Forms、Job Object清理、Windows原生扩展加载及首次浏览器自动打开；当前机器没有Windows或Wine，不能把Linux检查描述成Windows验收。没有真实模型密钥，未测试真实API。

安装包保留所有原始源码，可从app目录继续开发。Windows手动源码启动步骤仍见WINDOWS.md。
