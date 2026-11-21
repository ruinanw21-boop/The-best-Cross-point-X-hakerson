# Campus Cards · Text demo

## English

Open `CampusCards.xcodeproj` in Xcode, select the shared **CampusCards** scheme and an iPhone simulator, and press **⌘R**. The deployment target is iOS 18.0. To run on a physical iPhone, set your development team in **Signing & Capabilities** and use a bundle identifier available to that team.

### Demo walkthrough

1. On the English home screen, choose **New task → Submit enrollment documents → Create task**. Open **Show card** and try **Swap card languages**.
2. Choose **Record reply → Directions**. Enter `去学生服务中心`, review, and save.
3. Record a **Requirements** reply. Enter `周五下午四点前，把护照复印件交到一楼服务台。` In review, fill in the fields below. Under **Set an exact time**, choose Friday and set the clock from 4:00 p.m. to 3:30 p.m. Confirm and save.
4. Relaunch the app and open the task. The checklist should say **By 3:30 p.m. on Friday** and **周五下午三点半前**. The original reply should still say **四点**.
5. Create **Collect lost property**. Save a requirements reply with only the library reception location. Open the **What do I need to bring?** card and save a second reply with **Student ID / 学生证**. Check the item, complete the task, then reopen it.
6. Try the globe menu mid-reply. The current draft should stay open and the selected interface language should persist across launches.

| Field | English | 简体中文 |
| --- | --- | --- |
| Bring | A photocopy of your passport | 护照复印件 |
| Location | Service desk, Level 1 | 一楼服务台 |
| Lost-property location | Library reception | 图书馆前台 |

This demo uses keyboard entry, built-in bilingual questions, and local storage. The campus instructions are fictional.

## 简体中文

在 Xcode 打开 `CampusCards.xcodeproj`，选择共享的 **CampusCards** scheme 和任一 iPhone 模拟器，按 **⌘R**。项目最低支持 iOS 18.0。真机运行需在 **Signing & Capabilities** 选择开发团队，并使用该团队可用的 Bundle Identifier。

### 演示流程

1. 从英文首页新建「补交入学材料」，出示大字问句，再交换中英文顺序。
2. 录入「去学生服务中心」，选择「指路」，核对并保存。
3. 再录入一轮「办事要求」原话「周五下午四点前，把护照复印件交到一楼服务台。」按上表手填双语材料和地点。打开「设置明确时间」，选择周五，把 16:00 改成 15:30 后保存。
4. 重启 App 后打开该事项，清单中英文应显示下午三点半，历史原话仍保留「四点」。
5. 新建「领取失物」，先确认图书馆前台，再出示追问卡并补录学生证。勾选学生证、办结，再重新打开事项。
6. 录到一半时用地球图标切换界面语言，继续编辑原草稿。重启后检查语言偏好。

本版使用键盘、内置双语问句和本地存储。演示里的校园办事要求为虚构示例。
