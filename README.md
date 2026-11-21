# Bilingual Campus Cards

[English](#english) · [简体中文](#简体中文)

## English

**“Before I leave the counter, I know what to do next.”** Bilingual Campus Cards is a planned iPhone app for international students visiting a Chinese-speaking campus service desk for the first time. A student prepares a question in English, shows it in Chinese, checks the reply with the staff member, and leaves with a bilingual checklist they can reopen the next day.

**Track**　CrossPointX 2026 · Apple Human-Centered Care  
**Status**　Design stage. The Xcode project, runnable build, and demo link are pending. [Development plan (in Chinese)](双语办事卡_开发方案.md)

### From a question to a checklist

A student needs to submit an enrollment document. On the way, they need to know which desk to visit. At the desk, they need to know what to bring and when to come back. Both conversations belong to the same task.

| Stage | What happens | What the card keeps |
| --- | --- | --- |
| Prepare | The student enters a goal, chooses what to ask about, and checks the English wording. | A question in large Chinese text with English underneath. |
| Ask for directions | The student records the first person's directions and continues the task at the service desk. | Each reply in order, with the original wording. |
| Check together | The staff member dictates or types a reply. Both people can correct a field or ask about a missing detail. | A confirmed bilingual checklist of materials, deadlines, and locations. |
| Come back later | The student reopens the task, checks off an item, adds a requirement, or marks the task complete. | The agreed instructions, conversation history, and progress. |

For example, a staff member says, “周五四点前，把护照复印件交到一楼服务台。” The review screen would show the following fields. If the staff member corrects the deadline to 3:30 p.m., both versions of the saved checklist should show 3:30.

| Field | English | 中文 |
| --- | --- | --- |
| Bring | A photocopy of your passport | 护照复印件 |
| Deadline | By 4 p.m. on Friday | 周五下午四点前 |
| Location | Service desk, Level 1 | 一楼服务台 |

### Language controls

The interface will open in **English** on first launch, including on iPhones set to Chinese. Students can choose **English** or **简体中文** under **Language / 语言** on the home screen or within a task. The screen updates immediately, keeps the current draft, and remembers the choice after relaunch.

When a student shows the phone to someone, the card initially puts Chinese in large type with English underneath. They can swap the display order. The microphone has its own language selector so a staff member can dictate in Mandarin while the student keeps the interface in English.

### iOS implementation plan

The prototype targets **iPhone running iOS 18 or later**, using **Swift and Xcode**.

| Component | Approach |
| --- | --- |
| Interface | SwiftUI and `NavigationStack` for tasks, large-print cards, and a review screen showing the original reply alongside editable fields. A String Catalog holds both interface languages. |
| Input | Keyboard entry and tap-to-record dictation. Speech and `AVAudioEngine` handle transcription, which the user can edit before saving. |
| Translation and review | Reviewed bilingual templates cover common questions. Apple Translation’s `TranslationSession` handles free text. The app suggests materials, deadlines, and locations for the student and staff member to confirm. |
| Storage | SwiftData stores tasks, conversation turns, and checklist items. Each item points back to its source reply. Students can keep several tasks open and revisit completed ones. |

Before a device demo, configure the microphone and speech recognition permission descriptions and check the English and Chinese translation packs. The keyboard supports the full workflow in a noisy room or when microphone access is off. Saved cards and built-in questions can be viewed offline.

### Demo scenarios

1. **Start a new task.** Ask where to submit enrollment documents, record directions, then record the staff member’s reply. Correct the deadline at the counter and check that both languages agree.
2. **Resume another task.** Reopen yesterday’s lost water bottle inquiry, add the pickup requirement, and complete it. Return to the enrollment task and check its progress.
3. **Try an unscripted request.** Ask to borrow a projector adapter, enter a custom reply, close the app, and reopen the task where you left off.
4. **Switch languages mid-task.** On a fresh install with the iPhone set to Chinese, check that the app opens in English. Start typing a reply, switch to Chinese, and finish editing. Relaunch to check the language preference, then switch back to English.

During a user test, ask the student to put the phone away and explain what to bring, where to go, and by when. Have them reopen the card to see which detail they need to check.

## 简体中文

**《离开柜台前，我知道下一步做什么》** 是为第一次用中文在校园办事的国际新生设计的 iPhone 原型。学生出发前用英语写下要办的事，在路上出示中文问路卡，在柜台和工作人员一起核对答复，离开时带走一份可以照着做的双语清单。

**赛道**　CrossPointX 2026 · Apple Human-Centered Care  
**开发状态**　方案阶段。以下描述为原型目标。Xcode 工程、可运行构建和演示链接待提交。[开发方案](双语办事卡_开发方案.md)

### 一张卡怎样帮学生办完一件事

一名新生要补交入学材料。他在路上想问的是「我该去哪个柜台？」，到了柜台才需要知道「要带什么、最晚几点来？」。把这两次交流记在同一个事项里，第二天他还能找回工作人员确认过的要求。

| 环节 | 学生与工作人员的操作 | 卡片内容 |
| --- | --- | --- |
| 准备 | 学生输入办事目的，选择想问地点、材料或时间，用英文核对后把手机转向对方 | 大字中文问句，下方保留英文 |
| 问路 | 记录第一位同学指的方向，到目的地后继续用同一张卡追问 | 按顺序保留每次答复及原话 |
| 柜台核对 | 工作人员口述或打字，双方对照原话修改地点、材料和时间 | 确认后的中英双语行动清单，缺失信息可以继续追问 |
| 稍后继续 | 学生关掉 App，回来后打开原事项，勾选已准备的材料、补充要求或标记办结 | 已确认的信息、办理进度和交流记录 |

例如，工作人员说「周五四点前，把护照复印件交到一楼服务台」，核对页应给出下面三项。若工作人员当场把时间改成三点半，保存后的两种语言都应显示修正后的时间。

| | 中文 | English |
| --- | --- | --- |
| 材料 | 护照复印件 | A photocopy of your passport |
| 截止时间 | 周五下午四点前 | By 4 p.m. on Friday |
| 地点 | 一楼服务台 | Service desk, Level 1 |

### 语言切换

首次启动默认显示**英文**，即使 iPhone 的系统语言是中文。学生可在首页或事项内点开 **Language / 语言**，选择 **English** 或**简体中文**。当前页面立即换语言，保留正在编辑的草稿，下次打开沿用上次选择。

把手机递给别人时，卡片默认放大中文，下方保留英文，可以交换主次。麦克风旁可单独选择识别语言，学生用英文界面也能直接记录工作人员的普通话答复。

### iOS 实现计划

目标设备为 **iOS 18 或以上的 iPhone**，使用 **Swift 和 Xcode** 开发。

| 模块 | 技术与设计 |
| --- | --- |
| 界面 | SwiftUI 和 `NavigationStack`。首页按事项组织，出示时放大中文，核对时并排展示原话与可编辑字段。两种语言的界面文案统一放在 Xcode String Catalog。 |
| 输入 | 键盘输入和按次录音。Speech 与 `AVAudioEngine` 负责转写，用户可先修正识别结果。 |
| 翻译与整理 | 常见问句采用校对过的双语模板，自由输入使用 Apple Translation 的 `TranslationSession`。从答复中提取候选材料、时间和地点，由双方确认后保存。 |
| 数据 | SwiftData 分别保存事项、每轮交流和行动项。每个行动项关联来源答复，用户可同时办理多件事，也可重新打开已办结的事项。 |

真机演示前需配置麦克风与语音识别权限说明，并检查中英翻译语言包。现场嘈杂或麦克风权限关闭时，键盘仍能走完整个流程。已保存的双语卡和内置问句支持离线查看。

### Demo 验收场景

1. **新建一件事。** 用「补交入学材料」走完问路、柜台答复和现场纠正。检查两轮答复是否归入同一事项，两种语言的时间是否一致。
2. **继续另一件事。** 打开昨天的「领取遗失水杯」，补问领取条件并办结，再切回入学事项。检查两张卡各自保留了正确的内容和进度。
3. **让体验者出题。** 从空白事项输入一个新问题，例如借投影转接线，记录一条自定义答复。退出并重新打开 App，检查能否从上次的位置继续。
4. **中途切换语言。** 在中文系统上全新安装，确认首次进入是英文。录入答复到一半切换为中文，继续编辑；重启后检查语言偏好，再切回英文。

用户试用时，请学生收起手机，用自己的话复述要带什么、几点前去、去哪里。再请他打开卡片核对，观察哪项信息需要重新确认。
