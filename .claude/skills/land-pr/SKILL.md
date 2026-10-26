---
name: land-pr
description: Land a PR that a cloud session wrote without Xcode ("built blind") - check it out locally, make it compile, run the tests, review it against designs/, fix, then merge to main after the user confirms. Use when asked to "take over / bring locally / finish / merge PR <N>". Args - one or more PR numbers (stacked PRs land in order), plus optional `seed` (copy recent iCloud logs into the simulator) and `shot` (one screenshot of the changed screen).
---

# Land a built-blind PR

The user often has cloud sessions write code while they are away from the Mac.
Those PRs have never been compiled. This skill turns one into a merged,
tested change with as little token spend as possible: **never dump full
xcodebuild output into context**. Always redirect to a log and grep it.

Work in a worktree (EnterWorktree) unless the session already is in one.
Scratch files go in `$CLAUDE_JOB_DIR/tmp` if set, else `build/tmp`.

## 1. Understand the PR (cheap)

```sh
gh pr view <N> --json title,body,headRefName,baseRefName,state,mergeable,files,commits
```

- If `baseRefName` is not `main`, it is stacked: land the base PR first, then
  rebase this one onto main. When several numbers are given, order them
  base-first.
- Read `designs/INDEX.md` and only the design docs for the areas the PR's
  `files` touch, plus `designs/known-issues.md` for those areas.
- Check out: `gh pr checkout <N>`, then `git lfs pull` (test CSVs and nav.db
  are LFS pointers otherwise).

## 2. Build until it compiles

Pick a simulator by id: a `name=` destination resolves to `OS:latest` and fails
when that device only exists on an older runtime.

```sh
xcrun simctl list devices available | grep -E "iPhone 1[0-9]" | tail -4   # take one UDID
```

In a worktree session, a command that runs `xcodebuild` with `$VAR` paths is
refused (it can't be shown not to be git), so write the UDID and the log folder
(`$CLAUDE_JOB_DIR/tmp`, or `build/tmp`) out literally. Below, `<UDID>` and
`<LOG>` stand for them.

Don't pass `CODE_SIGNING_ALLOWED=NO`: an unsigned build has no keychain access
and `TestUploads/testKeychainStore` fails. Simulator builds sign ad hoc.

```sh
xcodebuild build-for-testing -project flightlogstats.xcodeproj -scheme FlightLogStats \
  -destination 'id=<UDID>' -derivedDataPath <LOG>/dd -skipMacroValidation \
  > <LOG>/build.log 2>&1; echo exit=$?
grep -E " error:|\*\* .*(SUCCEEDED|FAILED)" <LOG>/build.log | sort -u | head -40
```

Fix errors in the files the PR touched first. Typical blind-build failures:
new files not added to the Xcode target (`project.pbxproj`), wrong API
availability for the deployment target, `@MainActor` / Sendable isolation,
RZFlight or RZData APIs that don't exist yet. For the last one, per
CLAUDE.md, consider adding the API to the library (`~/Developer/public/rzflight`,
`rzutils`) instead of working around it. Say so before changing another repo.

## 3. Test

```sh
xcodebuild test-without-building -project flightlogstats.xcodeproj -scheme FlightLogStats \
  -destination 'id=<UDID>' -derivedDataPath <LOG>/dd -only-testing:FlightLogStatsTests \
  > <LOG>/test.log 2>&1; echo exit=$?
```

Run it in the background: xcodebuild can hang after the last test, past the Bash
timeout. Wait for `Test Suite 'Selected tests' (passed|failed)` in the log, then
summarise. The log is huge, so only grep it, and kill a hung xcodebuild:

```sh
grep -E "Test Case .*failed \(|error: -\[" <LOG>/test.log | sort -u | head -20
grep -cE "^Test Case .*passed" <LOG>/test.log
```

The per-suite `Executed N tests` lines are not the total; count the passed
cases. `TestParsingLogFiles/testFlightLogFile` has failed once in a full run and
passed alone (quick-parse start airport nil): rerun it alone before blaming the PR.

The full suite takes a few minutes. Iterate on a failure with
`-only-testing:FlightLogStatsTests/<TestClass>`, then re-run the whole suite
once at the end. If the PR adds logic with no tests, add at least one.

## 4. Review

Read the diff (`git diff main...HEAD -- <path>` one area at a time, not all at
once for big PRs). Check against the CLAUDE.md principles and the design docs:
- no `viewContext` off the main thread; new screens are SwiftUI with
  `@Observable` view models
- logic that belongs in RZFlight or RZData, and code duplicated from existing code
- the DEBUG test hooks still work: "Forget last" in DEBUG,
  `-FLSImportFolder <path>`, `-FLSShowUploads YES`
  (`Source/MainSplitViewController.swift`)
- derived vs user state for Core Data or CloudKit changes
  (`designs/plans/upload-and-import.md`)

Fix real problems. List nice-to-haves for the user instead of doing them.

## 5. Optional: seed and screenshot (only when asked: `seed`, `shot`)

The user usually checks the UI themselves, and that is cheaper, so skip this
unless asked. Install and seed the 10 most recent real flights:

```sh
BID=net.ro-z.flightlogstats
xcrun simctl boot <UDID> 2>/dev/null; xcrun simctl install booted "<LOG>/dd/Build/Products/Debug-iphonesimulator/FlightLogStats.app"
SRC=~/Library/Mobile\ Documents/iCloud~net~ro-z~flightlogstats/Documents
DST=$(xcrun simctl get_app_container booted $BID data)/Documents
xcrun simctl terminate booted $BID 2>/dev/null
(cd "$SRC" && find . -name 'log_2*.csv' -size +200k | sed 's|./||' | sort | tail -10 | while read f; do cp "$f" "$DST/"; done)
xcrun simctl launch booted $BID
```

`shot` means **one** screenshot of the changed screen
(`xcrun simctl io booted screenshot <LOG>/shot.png`, then Read it). Don't
navigate the UI step by step with screenshots. If the screen can't be reached
with a launch argument, say so and leave it to the user.

## 6. Land

1. Commit the fixes to the PR branch and push, so the PR shows what changed.
2. Sync design docs for modules the PR changed (`sync-designs` skill).
3. Report: what the PR does, what was broken and fixed, test result
   (`Executed N tests, 0 failures`), open nice-to-haves, and what the user
   should look at in the simulator.
4. **Ask before merging** unless the user already said to merge. Then
   `gh pr merge <N> --merge --delete-branch` (base PR first when stacked;
   rebase the next PR onto main and re-run step 3 before merging it).
5. `git fetch && git log --oneline -3 origin/main` to confirm the merge.
