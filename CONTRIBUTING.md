# Contributing files to this repository

The `main` branch contains the version used for demonstrations. Submit each task on a separate branch and obtain approval from one other contributor before merging it into `main`. The following steps use the GitHub website.

Before your first upload, sign in with the GitHub account that received the repository invitation and accept it. Then open the [project repository](https://github.com/ruinanw21-boop/The-best-Cross-point-X-hakerson).

## 1. Create a branch

1. On the **Code** tab, open the branch selector above the file list and select `main`.
2. Open the selector again and enter a name that describes the task, such as `docs/demo-script`. Select the option to create the branch from `main`.
3. Confirm that the selector now shows your new branch. If another contributor is editing the same file, agree on the changes before uploading a replacement.

## 2. Upload and commit the files

1. On your branch, open the folder where the files belong. For files that belong at the top level of the repository, use the folder that opens when you select **Code**.
2. Before uploading, check each file for passwords, API keys, and personal information, including details visible in screenshots. Keep credentials and local configuration files such as `.env` on your computer. When replacing an existing file, check that your copy includes the latest edits.
3. Select **Add file → Upload files** and choose only the files needed for this task. Check the filenames in the upload list.
4. Enter a short commit message describing the change, such as `Add speaker notes for the demo`. Select the option to commit to your current task branch and confirm the upload.

## 3. Open a pull request

1. Return to the repository and select **Compare & pull request**. If the banner is absent, select **Pull requests → New pull request**.
2. Set **base** to `main` (the destination) and **compare** to your task branch (the changes being submitted). Check the list of changed files.
3. Enter a descriptive title. In the description, explain what changed and how to verify it. For example, “Added speaker notes to the demo script. Open the Markdown preview and confirm that each slide has a corresponding note.”
4. Select **Create pull request** and share the link with another contributor for review. If revisions are needed, commit them to the same branch. GitHub updates the pull request automatically.

## 4. Review and merge

1. As the reviewer, open **Files changed**, inspect the additions and deletions, and follow the verification steps. If corrections are needed, leave feedback on the relevant lines. When the changes are ready, select **Review changes → Approve → Submit review**.
2. After approval, a contributor with write access can open **Conversation**, select the merge option, and confirm. The **Merged** status indicates that the changes are in `main`.

If GitHub reports a merge conflict, coordinate with the contributor who edited the affected file and verify the resolved version before merging. If a credential has been uploaded, revoke or rotate it with the issuing service immediately and notify the repository owner so they can address the exposure in the commit history.

For illustrated instructions, see [Uploading files on GitHub](https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository) and [Creating a pull request](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/creating-a-pull-request).
