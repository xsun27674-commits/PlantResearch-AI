# PlantResearch AI

面向植物科学的本地单用户科研工作台。Next.js / TypeScript / Tailwind CSS + FastAPI / SQLite。

## 安装与启动

需要 Python 3.12、Node.js 20.9+（本环境使用 Node 24）、npm。Linux/macOS：

```bash
cd /workspace/py_firework # 本地请换成实际克隆目录
bash scripts/install.sh
bash scripts/start.sh
```

在自己的电脑浏览器打开 http://127.0.0.1:3000 。云环境的 localhost 属于云机器；本项目尚未配置公网访问。后端仅监听 127.0.0.1:8000，前端代理 `/api` 请求。Ctrl+C 停止。Windows 可分别启动 `.venv\Scripts\python -m uvicorn backend.app:app --host 127.0.0.1 --port 8000` 与 `npm run dev --prefix frontend`。

生产模式本地验证：`cd frontend && npm run build && npm start`，另一个终端启动后端。请勿直接将此版本公开部署。

## 使用

1. 文献分析：上传不超过10 MB、200页的文本型 PDF，查看每页原文和元数据，下载原文 CSV/Excel。DOI 为原文候选，未经注册机构核验；元数据作者和标题也可能不准确。扫描PDF需要OCR，本版不提供。
2. 数据分析：上传 UTF-8 CSV 或 XLSX（首个工作表），查看前20行、类型、缺失值与描述性统计。最多50000行、100列，XLSX解压总大小限制50 MB。日期作为ISO文本保存。柱状图为前50组均值；散点图需要两个数值列；箱线图使用X数值列；热图为数值列Pearson相关系数。缺失数据不插补。下载统计表 CSV/Excel 或PNG图表。图表不包含显著性检验；本版未提供推断统计。
3. 科研助手：先上传材料再切换助手页。提交时会把本次页面已上传的论文和数据摘要发送到所选模型（当前最多100000字符上下文，长材料可能截断）。所有附件发送前请自行确认权限。助手输出物种、基因、方法、结论及页码/引文，但属于**未经自动核验的AI草稿**；不得当作已验证证据。下载助手结果会导出完整JSON文本。
4. 设置页检查密钥是否配置。没有密钥时基础功能全部可用，AI明确返回503，不生成模拟结论。模型失败返回502中文错误。

### 模型配置（可选）

启动前在终端设置环境变量，再启动或重启后端：

```bash
export DEEPSEEK_API_KEY='你的密钥'
# 或 export QWEN_API_KEY='你的密钥'
# 可选：DEEPSEEK_MODEL=deepseek-chat，QWEN_MODEL=qwen-plus
bash scripts/start.sh
```

不要把真实密钥提交到Git。代码不会自动加载.env。固定使用官方HTTPS端点，环境需要访问 api.deepseek.com 或 dashscope.aliyuncs.com。没有配置任何真实密钥，未验证真实模型输出。

## 测试

```bash
.venv/bin/python -m pytest backend/test_app.py -q
cd frontend && npm run build
```

集成测试覆盖真实生成PDF上传/页码文本/DOI候选、Excel上传预览/统计、四种PNG图表、CSV/Excel导出、无密钥和模型连接失败、错误文件和未知资源。

## 存储与隐私

SQLite在 `backend/private_data/tasks.sqlite`，可由 PLANT_DATA_DIR 修改。原始上传文件不落盘，提取文本与数据副本保存在SQLite；目录没有静态公开路由，文件名不作为路径，使用随机ID和参数化SQL。删除该目录会删除所有历史结果。页面刷新会丢失当前附件选择，但本地数据库仍保留结果。图表成功执行的参数记录在数据库；任务错误显示在页面，尚无后台队列、历史任务列表或流式进度。

没有认证、授权、CSRF防护、上传隔离进程或多用户隔离。随机ID不等于权限控制。只供可信本地单用户使用；不要绑定0.0.0.0或暴露代理服务。对恶意文档仍需未来通过独立进程与资源配额加固。CSV/Excel导出转义公式前缀。代码不执行用户/AI提供的代码。

## 架构与后续范围

- `backend/app.py`：固定PDF、统计和图表API，SQLite任务记录、模型适配；模型无法执行代码或自由调用工具。
- `backend/extensions.py`：ResearchAgent、Retriever、AccessPolicy 协议，为多Agent、RAG和数据隔离留接口；未实际实现这些服务。
- `frontend/app/page.tsx`：五个中文功能视图，响应式布局。
- 当前助手使用页面已上传材料进行总结。自然语言自主选择和调度绘图工具、自动核验结构化引用、多Agent、OCR、RAG、登录、云部署仍未实现。
- DeepSeek Harness评估：本版不引入。模型API与Agent执行框架是独立概念；未获得可核验的具体Harness仓库/版本，不能宣称已验证其兼容性。固定工具+明确的适配协议更适合当前范围；未来有实际项目链接后再评估许可、沙箱、可观测性和维护状态。

依赖固定在Python requirements与npm package-lock，运行无需外部数据库。PyMuPDF的开源许可及未来发布方式需在发布前确认；本项目尚未选择整体开源许可证。

## Windows 与云端预览

完整Windows安装、双终端启动、可选模型配置及排障见 [Windows指南](docs/WINDOWS.md)。云容器的127.0.0.1不等于Windows本机地址；当前会话没有可用的预览端口映射工具，不能将容器内部地址作为云端预览链接。

## Windows一键离线包

已有预发布的一键安装包：将 `PlantResearch-AI-Windows-x64.zip` 全部解压后双击 `Install.cmd`。内置Windows Python、Node、全部依赖和生产前端，用户无需命令行操作。详见 [打包与验证范围](docs/WINDOWS-PACKAGE.md)。此包在Linux组装，尚未在Windows实机验收。

## 已安装的Windows软件无法启动

下载启动修复分支源码后，关闭旧启动器，双击源码根目录的 `Repair-Startup.cmd`。它备份并更新启动代码，不重装依赖、不修改科研数据。诊断日志位置、已修复问题和Windows待验证范围见 [Windows启动修复](docs/WINDOWS-STARTUP-REPAIR.md)。
