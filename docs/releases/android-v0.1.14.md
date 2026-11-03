# CmuxRemote Android 0.1.14

The background-task bar now follows the iPhone's single-line layout.

## Conversation

- One line above the composer reads `N background tasks` with a chevron;
  tapping it lists each task as `• tool  summary  ›`, and tapping a row opens
  its own page.
- The duplicate "background tasks running" row and spinner inside the composer
  are gone. The bar itself does not spin; a task's running state is in its
  summary.
- The decorative gear from the summary line is removed, leaving the count and
  the expand chevron only.

## Verification

- 111 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- 410 matching Android strings per locale.
- The task-bar Compose test covers the collapsed summary and the expanded
  task list.

## Install

Download `CmuxRemote-Android-0.1.14.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
