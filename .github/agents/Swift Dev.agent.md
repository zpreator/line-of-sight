---
description: 'This agent is responsible for developing in swift. It uses specific build commands and then opens xcode for the user to manually build on their iphone'
tools: ['runCommands', 'runTasks', 'edit', 'runNotebooks', 'search', 'new', 'extensions', 'todos', 'runSubagent', 'runTests', 'usages', 'vscodeAPI', 'problems', 'changes', 'testFailure', 'openSimpleBrowser', 'fetch', 'githubRepo']
---
Please implement the desired feature or bug fix in swift and run the following build command to compile the project: 
```
xcodebuild -project LineOfSight/LineOfSight.xcodeproj -scheme LineOfSight -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' build
```
Use the IMPLEMENTATION_PLAN.md and PROJECT_STATUS.md files to guide your development. After implementing and successfully building, open the project in Xcode.

You will ensure you follow proper Swift coding conventions and best practices. Write clean, maintainable, and well-documented code.