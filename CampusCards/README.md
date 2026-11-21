# Campus Cards

## English

Open `CampusCards.xcodeproj` in Xcode, select the shared **CampusCards** scheme and an iPhone simulator, and press **⌘R**. The deployment target is iOS 18.0. To run on a physical iPhone, set your development team in **Signing & Capabilities** and use a bundle identifier available to that team.

Before building for offline speech, run `python3 CampusCards/Scripts/prepare_offline_speech.py` from the repository root. This verifies the multilingual base model and tokenizer and places them in the app's bundle resources. Open **Translate reply**, hold either microphone, release to transcribe, and tap **Play recording** to listen.

### Demo walkthrough

1. On the English home screen, tap **New task** and choose **Submit enrollment documents**. Use **Card preview**, then tap **Create task**. Open **Show card** to present the question. Tap the arrow between the languages to swap their order.
2. Choose **Translate reply → Directions**. Set the source language to Chinese and enter `去学生服务中心`. Tap **Translate to English**. On first use, enter the Windows service base address and tap **Save and translate**. Edit the result and tap **Confirm and save**.
3. Record a **Requirements** reply. Enter `周五下午四点前，把护照复印件交到一楼服务台。` In review, check the translation and expand **Action checklist** to fill in the fields. Under **Set an exact time**, choose Friday and set the clock from 4:00 p.m. to 3:30 p.m. Confirm and save.
4. Relaunch the app and open the task. The checklist should say **By 3:30 p.m. on Friday** and **周五下午三点半前**. Open **Conversation history** to verify that the original reply still says **四点**.
5. Create **Collect lost property**. Save a requirements reply with only the library reception location. Open the **What do I need to bring?** card and save a second reply with **Student ID / 学生证**. Check the item and mark the task complete. Return to **My tasks**, switch to **Completed** and reopen it.
6. Try the globe menu mid-reply. The current draft should stay open and the selected interface language should persist across launches.

| Field | English | 简体中文 |
| --- | --- | --- |
| Bring | A photocopy of your passport | 护照复印件 |
| Location | Service desk, Level 1 | 一楼服务台 |
| Lost-property location | Library reception | 图书馆前台 |

The app keeps pending replies and confirmed history on the device. Requesting a translation sends the reviewed source text and its language direction to the configured service. The campus instructions are fictional.

## 简体中文

在 Xcode 打开 `CampusCards.xcodeproj`，选择共享的 **CampusCards** scheme 和任一 iPhone 模拟器，按 **⌘R**。项目最低支持 iOS 18.0。真机运行需在 **Signing & Capabilities** 选择开发团队，并使用该团队可用的 Bundle Identifier。

### 演示流程

1. 从首页选择「新建事项 → 补交入学材料」，创建前可点「卡片预览」。创建后点「出示卡片」，用两种语言中间的箭头交换顺序。
2. 选择「翻译答复 → 指路」，把原文语言设为中文，输入「去学生服务中心」。点「翻译成英文」，首次使用时填写 Windows 服务地址，再点「保存并翻译」。检查或编辑译文后点「确认并保存」。
3. 再录入一轮「办事要求」原话「周五下午四点前，把护照复印件交到一楼服务台。」检查译文，展开「行动清单」，按上表手填双语材料和地点。打开「设置明确时间」，选择周五，把 16:00 改成 15:30 后保存。
4. 重启 App 后打开该事项，「清单」的中英文应显示下午三点半。在「交流记录」核对原话仍是「四点」。
5. 新建「领取失物」，先确认图书馆前台，再出示追问卡并补录学生证。勾选学生证并点「办结」，回首页切到「已办结」，打开事项后点「重新办理」。
6. 录到一半时用地球图标切换界面语言，继续编辑原草稿。重启后检查语言偏好。

演示里的校园办事要求为虚构示例。

### 03 离线录音、转写和回听

在 Mac 上从仓库根目录执行以下命令，再用 Xcode 构建 `CampusCards` App target。第一条命令下载任务指定的多语模型和 tokenizer，第二条命令可在断网时逐文件校验 SHA-256。Xcode 会将准备好的 `OfflineSpeech` 整个目录复制进 App。安装后首次转写直接从 App 包读取资源。更换 Mac 或重新克隆时需重新准备。

```sh
python3 CampusCards/Scripts/prepare_offline_speech.py
python3 CampusCards/Scripts/prepare_offline_speech.py --verify-only
```

模型使用 [Argmax 的 openai_whisper-base](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-base)，分词资源来自 [OpenAI 的 whisper-base](https://huggingface.co/openai/whisper-base/tree/e37978b90ca9030d5170a5c07aadb050351a65bb)。App target 固定使用 [WhisperKit v1.1.1](https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1)。如果构建时漏装资源，翻译页会显示提示，仍可回听和手动键入。

**在 iPhone 上分两步验收**

1. 安装已预置资源的 App，开启飞行模式并关闭 Wi-Fi，完全退出再冷启动。在事项 A 的「翻译答复」按住中文麦克风，说“请到一楼服务台”。松开后，在翻译页回听、改一个字，返回并保留草稿。另建事项 B，按住英文麦克风说 “Which desk should I go to?”，同样回听和核对。分别打开两张草稿检查原音。首次出现麦克风授权弹窗时，授权后再按住录音。也可在系统设置中关闭麦克风权限，检查已有文字仍能编辑并进入翻译页。
2. 恢复 Wi-Fi，打开其中一张草稿，用下方 05 的方法配置 Windows 翻译服务。发起翻译、核对并「确认并保存」，完全退出 App 再打开。在原事项的「交流记录」回听，确认播放的是对应语句，也能查到修改后的原文和译文。记录设备型号、iOS 版本及两轮实际转写。

`TaskDetailView → ReviewReplyView → ReplyCapture.recognize` 使用 PR #9 的 `ReplyRecognizer`。按下麦克风固定事项、草稿、版本和源语言，松开时交付录音。编辑或切换草稿后，旧转写返回时不会写入。每轮创建独立的 `Application Support/Recordings/<UUID>.wav` 文件。草稿及历史仅存相对路径，例如 `Recordings/7F9C309A-2447-4FAC-86FF-F89B226008B5.wav`。键入的答复可以没有录音。

### 05 真机联调

1. 在 Windows 的 04 工程目录启动已验收的翻译服务，保持窗口打开。使用原先只允许测试手机访问的入口时，在 PowerShell 运行以下命令。两台设备连接同一 Wi-Fi，Windows 的入站规则需允许这台手机访问 TCP 8000。

   ```powershell
   $wifiIP = Read-Host 'Windows 的 Wi-Fi IPv4 地址'
   $phoneIP = Read-Host 'iPhone 的 Wi-Fi IPv4 地址'
   .\.venv\Scripts\python.exe -m translation_service.iphone_check --host $wifiIP --phone $phoneIP
   ```

2. 用 Xcode 将本分支的 CampusCards 安装到 iPhone。进入「事项详情 → 翻译答复」，录入原文后点「翻译成英文」或「翻译成中文」。首次使用时输入服务根地址，例如 `http://192.168.1.23:8000`，用实际电脑地址替换示例 IP。点「保存并翻译」后允许 App 访问本地网络。可通过右上角更多菜单中的「翻译服务」修改地址。智谱密钥由 Windows 服务读取。
3. 第一轮选 English，键入 “Which desk should I go to?”，点「翻译成中文」。修改一处译文，选「取消 → 保留草稿并关闭」。「交流记录」此时应维持原来的条数。重新打开「翻译答复」，核对修改仍在，再点「确认并保存」。
4. 第二轮选「简体中文」，键入“请把护照复印件交到一楼服务台”，点「翻译成英文」。确认后退出并重开 App，原事项应有两轮新答复，各自保留核对后的译文。改过原文的记录可展开「最初原话」。
5. 验证重试时，先停掉 Windows 服务，再发起翻译。原文和行动字段应可继续编辑。用同一地址重启服务，点「重试翻译」，然后确认保存。

### 自动化用例和语音交接

在 Xcode 选择共享的 **CampusCards** scheme 和 iOS 18 或更新的 iPhone 模拟器，按 **⌘U** 运行测试。

| 验证内容 | 复现方式 |
| --- | --- |
| HTTP 请求与服务错误 | `TranslationClientTests` 拦截实际 URLSession 请求，检查两种方向、三个 JSON 字段、断网以及 400、502、504 的处理；乱序用例拦住 A、B 两个 HTTP 请求，先放行 B，再放行 A。 |
| 乱序及切换草稿 | `ReplyWorkflowTests` 先发 16:00 的 A，再发 15:30 的 B，先完成 B，随后投递 A 的成功或错误；也覆盖手改译文、换事项、改语言和转写中键入。 |
| 草稿恢复、正式保存 | 同一套测试恢复未完成的草稿，并在支持 SwiftData 的测试目标中模拟保存失败、以相同草稿 ID 重试和重复确认，重新打开磁盘库检查两轮答复。 |
| 本地转写与回听 | `OfflineSpeechTests` 使用任务单两句中英文合成语音和 App 包内的真实模型。`ReplyAudioTests` 覆盖逐轮文件、重新打开后解码，以及权限回调与松手的先后顺序。 |

**任务 05 当时的验证结果（2026-11-21）**

| 环境 | 实际结果 |
| --- | --- |
| Windows / WSL，Swift 6.4.3 | 5 项草稿 XCTest、6 项 HTTP XCTest 全部通过。所有 App 与测试 Swift 源文件通过语法解析。Linux 测试使用去除 SwiftData 注解的模型副本。 |
| Swift 客户端 → 04 Flask/Waitress，固定翻译器 | 经回环 HTTP 验证英译中、中译英和 502、504 的错误映射。 |
| iPhone Safari → 04 Windows 服务 → 智谱 | 此前两种方向均返回 HTTP 200，已在 Safari 核对。 |
| iOS 原生 App | 任务 05 交付时，原生 App 的 Xcode 测试、本地网络授权和真机历史回听尚待验收。 |
