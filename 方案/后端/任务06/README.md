# 任务 06 · 从截止时间和地点找回原话

同一项「交护照复印件」有两个来源。周五的截止时间改到 15:30，要回听第二轮；地点仍是一楼服务台，要显示第一轮键入的整句。可以先用两组 JSON 数据做界面预览，再在 iPhone 录入真实答复。预览里的 ID 是样例代号，录音路径是占位值。[界面预览数据](field-sources.json)

## 在 iPhone 录入两轮

1. 使用装有本地语音模型的 iOS 18+ 演示 App，iPhone 和运行任务 04 翻译服务的电脑连同一局域网。在核对页配置电脑地址，例如 `http://192.168.1.23:8000`。下面两轮先联网翻译并保存。
2. 选「新建事项 → 自定义事项」，中文名称填「补交材料」，中文问句填「护照复印件该何时交到哪里？」。勾选「地点」「要带什么」「时间要求」，点「创建事项」。
3. **第一轮，键入。** 点「记录答复」，选「办事要求」和「简体中文」。键入“周五四点前，把护照复印件交到一楼服务台”。点「核对答复 → 翻译成英文」。在字段中填地点「一楼服务台」、材料「护照复印件」，打开「设置明确时间」，选周五 16:00，保留「最晚在此时间前到达」，点「确认时间」，再点「确认并保存」。此轮没有录音。
4. **第二轮，真人录音。** 回到同一事项，在已有的「时间要求」行点「… → 修正要求」。按住「按住说中文」，说“改到下午三点半，地点不变”。首次授权若中断，授权后重新按住录制。松手后等转写结束，点「回听本轮录音」核对内容，点「翻译成英文」。点「编辑时间」，将继承的周五 16:00 改为 **15:30**，保留周五和截止属性，点「确认时间」并保存答复。这次只修正时间。
5. 先在「交流记录」检查两轮的顺序、第一轮整句和第二轮回听。界面接好图谱后，打开同一事项的图谱，点行动「交护照复印件」，按下表逐个点字段。图中预期共 4 个节点（1 事项、2 答复、1 行动）。
6. **离线重开。** 开启飞行模式并确认 Wi-Fi 已关闭，从 App 切换器划掉 App，重新打开「补交材料」。再点一次截止时间和地点。听到同一段第二轮录音，并读到同一句第一轮原话才算通过。在已有「交流记录」中回听可单独验证本地录音，图谱点按需在接好图谱的版本验收。

| 行动字段 | 第二轮保存后的值 | 点开后的预期 |
| --- | --- | --- |
| 截止时间 | 周五 15:30 前 | 第二轮。显示初始转写，能听见“改到下午三点半，地点不变”。 |
| 地点 | 一楼服务台 | 第一轮。显示“周五四点前，把护照复印件交到一楼服务台”。 |
| 材料 | 护照复印件 | 第一轮。同一句键入原话。 |

## 对照 · 只在同一轮手改时间

另建事项「补交材料（同轮手改）」，重复第一轮输入。核对页先设周五 16:00 并点「确认时间」，然后在**第一次保存答复前**点「编辑时间」，选 15:30 并再次确认该时间，保留原句“四点前”。只保存一次。预览和接入后的期望是 1 个事项、1 轮答复、1 个行动；截止时间仍指向这一轮，同时显示原话和“用户核对时修改”。这个用例的截止时间 `userEdited = true`，地点和材料为 `false`。前一个两轮样例的三个字段均为 `false`。

## 数据接入位置

图谱打开一个事项时，在主线程调用 `let snapshot = try TaskStore(context: context).loadTask(taskID)`。一次读取包含事项、按保存顺序排列的答复，以及按创建顺序排列的行动和字段。保存新答复后重新读取即可。当前 App 的清单和录音回听入口在「事项详情」。[读取接口](../../../CampusCards/CampusCards/Persistence/TaskStore.swift) · [返回类型](../../../CampusCards/CampusCards/Persistence/TaskReadback.swift)

| 交给界面的数据 | 从当前模型读取 |
| --- | --- |
| 事项节点 | `snapshot.task.id` 和双语标题 `title`。 |
| 答复节点 | `snapshot.turns` 中每轮都有稳定的 `id`。初始原话取 `originalText`，核对后原文取 `confirmedText`，译文取 `translation`。旧轮次若缺少初始原话，可显示核对原文并标注。 |
| 行动节点 | `snapshot.actions` 中每个行动有稳定的 `id`。每个字段也有自己的 `id`，同一行动可以有多份材料。 |
| 行动字段与跳转 | `field.field` 为类型，`field.value` 为双语显示值，明确时间另有 `time`。`snapshot.source(for: field)` 按 `sourceTurnID` 找回该轮答复。`field.userEdited` 表示该字段在来源轮核对时标为手改。旧数据缺少此记录时为 `false`。 |
| 缺少字段 | 显示「待问」，没有来源可点。 |
| 回听 | 读取目标答复的 `recordingRef`。键入轮为 `nil`，录音轮由设备生成 `Recordings/<独立 UUID>.wav`，由 `ReplyRecordingFiles.url(for:)` 在本机 Application Support 下解析。沿用 `RecordingPlaybackButton(recordingRef:)`，实际文件名由录音模块分配。 |

[答复模型](../../../CampusCards/CampusCards/Models/ConversationTurn.swift) · [行动字段](../../../CampusCards/CampusCards/Models/ActionItem.swift) · [保存与更正](../../../CampusCards/CampusCards/Persistence/TaskStore.swift) · [录音与回听](../../../CampusCards/CampusCards/Features/ReplyAudio.swift)

地点和材料共用一条指向第一轮的图线时，仍须保留各自的字段依据。旧版本保存的字段会根据首次写入的时间戳恢复行动分组。若创建记录缺失或有冲突，该字段单独显示。

## 保存更正和更新进度

图谱编辑已有行动时，用 `ReplyDraft(taskID: taskID, correctingActionID: action.id, changes: fields)` 建草稿，再照常调用 `confirmReply`。传入本轮确认的字段；选中某份材料时，将 `FieldDraft.targetFieldID` 设为那一行的 `id`。字段缺失时可在该行动上补填。同值字段保留原来源和勾选状态。柜台另提新要求时用普通 `ReplyDraft(taskID: taskID)`，重试时复用同一份草稿。

按行动 ID 调用 `setItemDone(itemID: action.id, done: true)` 可一次勾选该行动的字段。原清单的材料按钮继续单独勾选所选材料。按事项 ID 调用 `setTaskCompleted(taskID: taskID, completed: true)` 办结，传入 `false` 重开。`listTasks()` 将进行中的事项排在前面，每组按最近更新时间排序。

## SwiftData 读回样例

在本 PR 的 GitHub Actions 运行页下载 `task-readback`。其中的 JSON 由示例程序用上述演示文字和预填译文写入临时数据库，重新打开后调用 `loadTask` 生成。ID 由运行时分配。iPhone 的录音、回放和图谱点按留待集成版验收。[样例程序](../../../CampusCards/Scripts/ExportTaskReadback.swift)

`beforeCorrection` 和 `twoTurnCorrection` 是同一事项改时前后的结果，可直接比较行动 ID 和三个字段的来源。`afterRetry` 是追加学生证并重试后的结果。示例的录音引用只演示相对路径格式，音频由真机录入时生成。
