# Bilingual Campus Cards · 双语办事卡

An iPhone app for international students visiting Chinese-speaking campus service desks. A student can show a question in Chinese, check the reply with the person at the counter, and leave with a bilingual checklist of what to bring, where to go, and when to return. Each checklist item links back to the reply it came from.

CrossPointX 2026 · Apple Human-Centered Care · iOS 18+ · [简体中文](#简体中文)

## At the service desk

1. **Prepare a question.** Choose a scenario such as submitting enrollment documents or collecting lost property, or write a custom card. Show the Chinese question in large type with the English underneath.
2. **Check the reply together.** Type the reply or record it in Mandarin or English. Review the transcript, request a translation or enter one manually, and fill in the checklist with the staff member.
3. **Keep the correction.** Suppose the staff member says “周五下午四点前，把护照复印件交到一楼服务台,” then corrects the deadline to 3:30 p.m. Set the deadline to 3:30 and save. Reopen the task to see the corrected time in both languages. Tap **View source** on the deadline to read the reply that said 4:00.

## Run the prototype

Clone the repository on a Mac with Xcode installed. From the repository root, run the following commands to prepare the speech model and open the project. The first command needs an internet connection on its first run.

```sh
python3 CampusCards/Scripts/prepare_offline_speech.py
open CampusCards/CampusCards.xcodeproj
```

Select the **CampusCards** scheme and an iPhone simulator running iOS 18 or later, then press **⌘R**. For a first walkthrough, choose **New task → Submit enrollment documents**. Use **Enter translation manually** to try the checklist without configuring a model API key. [iOS walkthrough and physical-device setup](CampusCards/README.md)

## Technology and data

| Component | Implementation |
| --- | --- |
| iPhone app | Swift and SwiftUI for the bilingual interface. SwiftData stores tasks, replies, and checklist items on the device. |
| Speech | WhisperKit transcribes Mandarin and English on the device using a bundled multilingual Whisper base model. Recordings stay on the phone and can be replayed when reviewing a reply. |
| Translation | The app sends the reviewed text and language direction to a Python service built with Flask, Waitress, and HTTPX. The service calls Zhipu’s `glm-5.3` API. Configure `ZHIPUAI_API_KEY` on the computer running the service. [Translation service setup](translation_service/README.md) |

The team used OpenAI Codex to assist with development.

## 简体中文

双语办事卡是一款为国际学生设计的 iPhone 应用。学生到校园服务窗口办事时，可以出示中文问句，和工作人员一起核对答复，把要带的材料、办理地点和截止时间存成一张双语清单。离开柜台后，点开清单上的一项，就能查到这条要求来自哪次答复。

### 在柜台试一次

1. 新建「补交入学材料」，选择想问的事项，在「出示卡片」中把大字中文问句给工作人员看。也可以从「领取失物」开始，或自写一张办事卡。
2. 工作人员说「周五下午四点前，把护照复印件交到一楼服务台」。键入这句话，或按住中文麦克风录音。双方核对原文和译文，再在行动清单里填入材料、地点和时间。
3. 如果工作人员当场把时间改成了下午三点半，把清单的截止时间改为 15:30，确认保存。退出再打开事项，中英文清单都会显示三点半；点开截止时间的来源，仍能看到最初说的「四点」。

### 运行与数据

在装有 Xcode 的 Mac 上，从仓库根目录运行上方两条命令，准备离线语音模型并打开工程。选择 **CampusCards** 和 iOS 18 或更高版本的 iPhone 模拟器，按 **⌘R**。首次进入默认使用英文，可在首页的语言菜单切换为简体中文。[iOS 运行与真机演示指南](CampusCards/README.md)

录音和中英文语音转写都在设备上完成，事项与清单由 SwiftData 保存在本机。需要自动翻译时，App 才将核对过的文字和翻译方向发给 Python 服务，由服务调用智谱 `glm-5.3`。没有配置翻译服务时，也可以手动输入译文，继续核对和保存。[翻译服务配置](translation_service/README.md)

## License

This project is licensed under the [Apache License 2.0](LICENSE).
