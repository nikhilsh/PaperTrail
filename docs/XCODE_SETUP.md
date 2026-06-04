# Xcode Setup

## Goal
Create the first local Xcode project for PaperTrail with a structure that matches the repo planning docs.

## Recommended project settings
- App name: `PaperTrail`
- Interface: `SwiftUI`
- Language: `Swift`
- Testing: include unit tests
- Core Data: **unchecked** at creation time if you want manual setup later, or checked if you want Xcode to scaffold a starting stack you can refactor
- Swift Testing / XCTest: your preference, but keep tests enabled

## My recommendation
Create a plain SwiftUI app target first, then add persistence deliberately.

Reason:
- cleaner architecture choices
- less Xcode-generated noise
- easier to control folder structure

## Deployment target
Pick a modern iOS baseline that still feels reasonable for the intended audience.

Suggested starting point:
- iOS 17+

That gives you:
- modern SwiftUI APIs
- fewer compatibility contortions
- a simpler v1

## Initial local project steps
1. Create the Xcode project locally.
2. Name it `PaperTrail`.
3. Save it into the cloned repo root.
4. Ensure the `.xcodeproj` and app folder live cleanly at the top level.
5. Match groups/folders to `PROJECT_STRUCTURE.md`.

## What to commit early
The first useful local commit after project creation should include:
- `.xcodeproj`
- app entry point
- basic folder/group structure
- placeholder screens compiling successfully

## Avoid early mess
- do not let everything live in one giant folder
- do not put business logic directly into SwiftUI views
- do not wire CloudKit on day zero before the local structure exists
- do not over-generate files you do not need

## Suggested first run target
A compilable shell with:
- app launch
- root navigation
- placeholder Library screen
- add button stub
- Settings entry

That is enough to prove the project skeleton is alive.
