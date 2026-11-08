# 第一版验证记录

当前云环境 Python 3.12 / Node 24。

- `bash scripts/install.sh` 重复安装成功（冻结Python依赖、npm ci）。请先停止服务再刷新依赖。
- `python -m pytest backend/test_app.py -q`：5 passed。Starlette测试客户端有弃用警告，当前无失败。
- `npm run build --prefix frontend`：构建和TypeScript检查通过。
- 系统Chromium + Playwright实际浏览器检查：首页、Excel上传预览、生成PNG、下载Excel、PDF上传文本、无密钥错误，800px平板视口无JS异常。
- 前端代理健康请求：200，status=ok。
- 未测试真实DeepSeek/Qwen服务：没有真实密钥。故障测试通过模拟连接异常验证502提示，并未生成模拟科研结论。
- 物种/基因/方法/结论及页码引用由模型提示约束，未完成机器可验证的结构化引用抽取；不能宣称科研语义验收通过。
- 科研助手固定关键词“描述性统计”“缺失值”“数据预览”“提取原文”“提取文本”可在有对应附件时运行本地工具，不需要密钥。其余任务调用模型材料总结；自主绘图调度仍待开发。

当前为功能MVP，非公共网站安全验收。未来需要真实科研样本、领域专家核验及多用户安全设计。
