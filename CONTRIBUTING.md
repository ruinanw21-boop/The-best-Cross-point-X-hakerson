# 队友怎么上传文件到 GitHub

用浏览器就能完成。我们的 `main` 分支用来演示。每次改动先传到自己的任务分支，再开一个 PR（合并请求），请另一位队友检查后合并。

第一次参与时，先用受邀的 GitHub 账号接受协作邀请，再打开[项目仓库](https://github.com/ruinanw21-boop/The-best-Cross-point-X-hakerson)。

## 1. 为这次任务建分支

1. 在仓库的 **Code** 页，点文件列表上方的分支名，切到 `main`。
2. 再点一次分支名，输入能说明任务的名字，例如 `docs/demo-script`。点 **Create branch … from 'main'**。
3. 看一眼文件列表上方。显示刚建的分支名，就可以开始上传了。如果两个人都要改同一个文件，先在群里商量好各改哪部分。

## 2. 选文件并提交

1. 在自己的分支里打开准备存放文件的目录。如果文件应该放在项目根目录，就留在 **Code** 首页。点 **Add file → Upload files**。
2. 只选本次任务需要的文件，逐个核对名称和内容。密码、API 密钥、`.env` 和带个人信息的截图都留在本机。上传同名文件会更新已有内容，先确认本地版本包含队友最近的修改。
3. 在 **Commit changes** 区域写一句具体的说明，例如“补充路演演示步骤”。确认提交目标是自己的任务分支，点击提交按钮。

## 3. 开 PR，请队友看一眼

1. 回到仓库首页，点 **Compare & pull request**。如果没看到这个按钮，点 **Pull requests → New pull request**。
2. 确认 **base** 是接收改动的 `main`，**compare** 是自己的任务分支。检查页面下方的文件变更，确认只包含这次要交的内容。
3. 写一个能说明改动的标题，再用一两句话告诉队友怎么验证。例如，“更新了演示稿。请打开预览，确认步骤顺序和两张配图都正确。”
4. 点 **Create pull request**，把 PR 链接发给一位队友。需要修改时，继续提交到同一个分支，原 PR 会自动更新。

## 4. 审核并合并

收到 PR 的队友打开 **Files changed**，检查改动和删除的内容，按说明验证一次。通过后点 **Review changes → Approve → Submit review**。然后回到 **Conversation**，由一人点击合并按钮并确认。看到紫色的 **Merged**，文件就已经进入 `main`。

如果页面提示 **conflicts**，把 PR 链接发给改过同一文件的队友，一起确认需要保留的内容。若误传了真实密钥，立即到对应服务撤销或更换密钥，再通知负责人处理提交记录。

[GitHub 网页上传说明](https://docs.github.com/zh/repositories/working-with-files/managing-files/adding-a-file-to-a-repository) · [创建 PR 的官方图解](https://docs.github.com/zh/pull-requests/how-tos/create-pull-requests/creating-a-pull-request)
