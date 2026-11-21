# 双语办事卡翻译服务

Windows 运行 Python 服务，iPhone 把用户核对过的文字和语言方向发到 `POST /translate`，收到的译文回到核对页。服务使用智谱 `glm-5.3`，API 密钥只配置在运行服务的电脑上。

## 在 Windows 上启动

在仓库根目录打开 PowerShell。首次使用先创建虚拟环境并安装依赖。

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\translation_service\requirements.txt
```

在智谱开放平台创建产品类型为「模型标准 API」的 API Key。如果当前终端还没有 `ZHIPUAI_API_KEY`，下列命令会提示输入并隐藏密钥。密钥保存在当前 PowerShell 会话及其子进程的环境中。启动后保持这个窗口打开，按 Ctrl+C 可以停止服务。[智谱快速开始](https://docs.bigmodel.cn/cn/guide/start/quick-start)

```powershell
if (-not $env:ZHIPUAI_API_KEY) {
    $secret = Read-Host '输入智谱模型标准 API Key' -AsSecureString
    $env:ZHIPUAI_API_KEY = [System.Net.NetworkCredential]::new('', $secret).Password
    Remove-Variable secret
}
.\.venv\Scripts\python.exe -m translation_service
```

默认地址为 `http://127.0.0.1:8000`。在另一个 PowerShell 窗口运行以下两组请求。请求体显式编码为 UTF-8，可在 Windows PowerShell 5.1 中发送中文。

```powershell
$uri = 'http://127.0.0.1:8000/translate'
$english = @{
    text = 'Which desk should I go to?'
    source_language = 'en'
    target_language = 'zh'
} | ConvertTo-Json -Compress
$chinese = @{
    text = '请把护照复印件交到一楼服务台。'
    source_language = 'zh'
    target_language = 'en'
} | ConvertTo-Json -Compress

Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($english))
Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($chinese))
```

两次成功请求均应返回 HTTP 200 和一个 `translation` 字段。英译中可返回 `{"translation":"我应该去哪个服务台？"}`。中译英可返回 `{"translation":"Please take a copy of your passport to the service desk on the first floor."}`。验收时核对问路意图，以及护照复印件、一楼、服务台三项信息。

### 上游模型与校园术语

服务使用 `httpx` 将请求发到智谱国内标准 REST 接口 `https://open.bigmodel.cn/api/paas/v4/chat/completions`，模型固定为 `glm-5.3`。模型启用思考，服务仅把最终译文返回给 iPhone。服务到智谱的连接超时为 15 秒，读取超时为 90 秒。真实调用按该账号的模型标准 API 规则计量。[GLM-5.3 调用示例](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3) · [思考模式](https://docs.bigmodel.cn/cn/guide/capabilities/thinking-mode)

有团队核实过的校园术语时，在启动窗口设置 `TRANSLATION_TERMS_JSON`，值为 JSON 数组，如 `[{"zh":"已核实的中文名","en":"Verified English name"}]`。请把占位文本换成实际名称。服务根据请求方向，将每个词条的原文和对应译名写入模型的 `system` 消息。没有核实过的词条时留空即可。

## 用 iPhone Safari 验收任务 04

在 Windows 的 Wi-Fi 详情或 `ipconfig` 中找到无线网卡的 IPv4 地址。在 iPhone「设置 → Wi-Fi → 当前网络旁的 ⓘ」找到手机的 IPv4 地址。从项目根目录运行以下命令；服务会提示在 Windows 隐藏输入密钥。

```powershell
$wifiIP = Read-Host 'Windows 的 Wi-Fi IPv4 地址'
$phoneIP = Read-Host 'iPhone 的 Wi-Fi IPv4 地址'
.\.venv\Scripts\python.exe -m translation_service.iphone_check --host $wifiIP --phone $phoneIP
```

1. 用这台 iPhone 的 Safari 打开 `http://电脑的Wi-Fi地址:8000/`，点「测试双向翻译」。页面依次调用正式的 `POST /translate`。服务只接受指定手机地址发来的请求。
2. 在手机上核对中文问句和英文答复中的护照复印件、楼层、服务台。点「我已看到两条译文」，页面会把显示结果发回 Windows 核对。终端两条 `HTTP 200` 加上 `IPHONE_CHECK displayed` 即为验收证据。
3. 测试结束后在服务窗口按 Ctrl+C。若 Safari 连页面都打不开，先核对两个设备当前的 Wi-Fi 地址。跨子网能否互访取决于网络路由和访问策略；可用 Windows 移动热点把 iPhone 直连到电脑，重新读取两台设备的地址再启动服务。

## 任务 05 如何从 iPhone 调用

1. 在原窗口按 Ctrl+C，用下面的命令启动局域网监听。在另一窗口运行 `ipconfig`，查找与 iPhone 同一网络的 WLAN 或以太网适配器的 IPv4 地址。

   ```powershell
   .\.venv\Scripts\python.exe -m translation_service --host 0.0.0.0 --port 8000
   ```

2. 假设该地址是 `192.168.1.23`，在演示 App 中配置服务地址 `http://192.168.1.23:8000`。客户端追加 `/translate`。手机上的 `localhost` 会指向手机本身。真机联调需要手机能访问电脑的 8000 端口，演示 App 允许访问本地网络和所用的本地 HTTP 地址。
3. 请求头使用 `Content-Type: application/json`。正文只包含 `text`、`source_language`、`target_language`，语言方向为 `en → zh` 或 `zh → en`。录音、事项 ID、草稿 ID 和版本号保留在手机上。

| 响应 | 客户端处理 |
| --- | --- |
| 200 和 `{"translation":"…"}` | 将译文送回对应草稿的核对页 |
| 400 和 `{"error":{"code":"invalid_request"}}` | 检查字段、空白文本和语言方向，修正后再提交 |
| 502 和 `{"error":{"code":"translation_failed"}}` | 保留草稿，稍后重试 |
| 504 和 `{"error":{"code":"upstream_timeout"}}` | 保留草稿，稍后重试 |

## 离线检查接口

安装依赖后，在仓库根目录运行。测试使用翻译器替身，可在没有 API 密钥时检查双向响应、无效请求、失败与重试。

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s translation_service -p "test_*.py"
```

**给核对页复现重试**　在未设置 `ZHIPUAI_API_KEY` 的终端直接启动服务，发送上面的英文请求，会得到 `502 translation_failed`。核对页应保留英文草稿。停止服务，配置有效密钥并在同一地址重新启动，再从原草稿点重试。上面的自动化测试可离线复现 504 超时。

## 既有验收记录（2026-11-21）

| 项目 | 结果 |
| --- | --- |
| Windows 自动化测试 | 14 项通过，包括 10 项翻译服务测试和 4 项手机验收页测试。后者覆盖来源限制、双向结果匹配、失败路径和显示确认。 |
| Windows 本机 HTTP | 2026-11-21，通过运行中的 `POST /translate` 各发一次英译中和中译英，两次均返回 HTTP 200。 |
| 先前模型的智谱调用 | 复测 `glm-4.7-flash` 得到 HTTP 429、业务码 `1305`，表示当时该模型访问量过大。[智谱错误码](https://docs.bigmodel.cn/cn/api/api-code) |
| GLM-5.3 英译中 | “Which desk should I go to?” → “我该去哪个服务台？” |
| GLM-5.3 中译英 | “请把护照复印件交到一楼服务台。” → “Please submit a copy of your passport to the service desk on the first floor.” |
| iPhone Safari 真机 | 2026-11-21 14:37（北京时间），指定 iPhone 通过 Wi-Fi 打开 Windows 验收页，英译中、中译英均收到 HTTP 200。14:37:40 收到页面显示确认，内容与两次响应逐项一致。 |
| iPhone 屏幕上的译文 | 英译中为“我该去哪个服务台？”，中译英为“Please submit a copy of your passport at the service desk on the first floor.”。原生 App 核对页在任务 05 中联调。 |
