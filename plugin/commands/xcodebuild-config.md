---
name: xcodebuild-config
description: How this repository is built and run with xcodebuild — read the configuration settled in .hq/xcodebuild-config.md, or settle it with the user once and write that file. Use before running xcodebuild or xcrun simctl in a repository, and to make the configuration again
allowed-tools: Bash(bash:*), Bash(git:*), Bash(mkdir:*), Bash(xcodebuild:*), Bash(xcrun:*), Bash(open:*), Read, Glob, Write
---

# XCODEBUILD-CONFIG — settle how this repository builds and runs, once

Building and launching an iOS app from the shell takes two commands, and
every argument of them is a choice: the workspace or project, the scheme, the
simulator device, its OS. This module settles those choices with the user
once and writes them to `.hq/xcodebuild-config.md`, a tracked file of the
repository; every later invocation reads that file instead of asking again.
**The choices are the user's.** You find the candidates, keep the commands
honest, and write nothing else in the tree.

Two readers rely on the file: `hq:plan`, which lifts its Build Command
verbatim when a plan's floor is a bare build; and whoever is about to
run `xcodebuild` in this repository — you, most often.

iOS simulators only. A macOS target, a physical device, or a Swift package
with no workspace or project has no configuration here; say so and stop.

## Context

- Settled configuration: !`bash -c 'r=$(git rev-parse --show-toplevel 2>/dev/null) || { echo none; exit 0; }; [ -f "$r/.hq/xcodebuild-config.md" ] && cat "$r/.hq/xcodebuild-config.md" || echo none'`

**The line printed the file** — the configuration is settled. Use its Build
Command and Run Command as they stand; compose no variant of either. Go on to
§ Procedure only when the user asked for the configuration to be made again,
or a command in the file no longer runs here — a scheme renamed, a runtime
removed — and say which before you do.

**The line says `none`** — no repository here, or the configuration was never
made. Go on to § Procedure.

## Procedure

Every command below is run by you and read by you, and none of them changes
the project. They are shown in plain fences because their arguments are
decided as you go; the one thing this module writes is the file in step 6.

**1. Find the project and its schemes.**

Glob the repository root for `*.xcworkspace` and `*.xcodeproj`. A workspace
wins when both are there — the project inside it is built through the
workspace. Neither: there is nothing to configure; say so and stop.

```
xcodebuild -list -json -workspace '<file>'
```

(`-project '<file>'` for a project; the same pair applies to every command
below.) **The quotes are part of every command here and in the file**: a
workspace, project, or scheme named with a space splits into two words
without them, and `xcodebuild` reads the second as a build action. The
`schemes` array is the candidate list. One scheme: take it. More than one:
put them to the user as a numbered list and wait for a number.

**2. Read the settings the commands will depend on.**

```
xcodebuild -showBuildSettings -workspace '<file>' -scheme '<scheme>' -sdk iphonesimulator
```

**It prints one block per target the scheme builds**, and a scheme with an
extension — a notification, share, or widget extension — prints the app's
block and the extension's side by side. The block that matters is the one
whose `PRODUCT_TYPE` is `com.apple.product-type.application`; an
extension's `PRODUCT_BUNDLE_IDENTIFIER` is its own, and launching it starts
nothing. From that block, four lines — `IPHONEOS_DEPLOYMENT_TARGET`, the
lowest OS the app runs on; `PRODUCT_BUNDLE_IDENTIFIER`, what the Run Command
launches; `BUILT_PRODUCTS_DIR` and `FULL_PRODUCT_NAME`, which together locate
the built `.app`. Report the four values. `-sdk iphonesimulator` is what
makes the directory the simulator's rather than the device's.

**The `.app` path is not written into the file.** `BUILT_PRODUCTS_DIR` sits
under a DerivedData directory whose name carries a hash of the project's
path, so it differs from one worktree to the next; the Run Command derives it
at run time from the same two settings.

**3. Choose the OS.**

```
xcrun simctl list runtimes available -j
```

Present the iOS runtimes as a numbered list of versions, each marked as at or
above the deployment target, or below it. **Suggest the lowest version at or
above the target** — that is where a compatibility break shows first — and
wait for a number.

No runtime at or above the target: say so, name the way to get one —
`xcodebuild -downloadPlatform iOS` — and stop; the configuration cannot be
settled without one.

**4. Choose the device.**

```
xcrun simctl list devices available -j
```

Present the devices of the chosen runtime as a numbered list — iPhones first,
then iPads, smallest first within each — suggest the smallest iPhone, and
wait for a number.

Then look the chosen name up in the other runtimes. Xcode creates one device
set per runtime, so the same name is usually there several times over, and
`simctl` addresses a device by name or by UDID with no OS qualifier — a bare
name is ambiguous. That is why the Run Command resolves the UDID at run time
from name **and** OS; say so when the name is duplicated. Never write a UDID
into the file: simulators get recreated, and their UDIDs change with them.

**5. Compose the two commands and run the first.**

The Build Command:

```
xcodebuild build -quiet -workspace '<file>' -scheme '<scheme>' -destination 'platform=iOS Simulator,name=<device name>,OS=<version>'
```

`name=` and `OS=`, never `id=` — a UDID in the destination breaks the day the
simulator is recreated. `-quiet` leaves only warnings and errors on the
output, and the exit code says whether it built; that is the form a plan's
the floor can run.

The Run Command — resolve, boot, locate, install, launch:

```
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
matches = [d['udid'] for rt, ds in devices.items() if rt.endswith('.iOS-<dashed version>') for d in ds if d['name'] == '<device name>']
if not matches: sys.exit('no available simulator: <device name> (iOS <version>)')
print(matches[0])
")
xcrun simctl bootstatus "$UDID" -b
open -a Simulator
APP=$(xcodebuild -showBuildSettings -json -workspace '<file>' -scheme '<scheme>' -sdk iphonesimulator 2>/dev/null | python3 -c "
import json, sys
apps = [t['buildSettings'] for t in json.load(sys.stdin) if t['buildSettings'].get('PRODUCT_TYPE') == 'com.apple.product-type.application' and t['buildSettings'].get('PLATFORM_NAME') == 'iphonesimulator']
if not apps: sys.exit('no iOS application target in scheme <scheme>')
print(apps[0]['BUILT_PRODUCTS_DIR'] + '/' + apps[0]['FULL_PRODUCT_NAME'])
")
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" <bundle identifier>
```

`<dashed version>` is the version with its dots turned to dashes — `26.5`
becomes `26-5` — because that is how the runtime identifier ends
(`com.apple.CoreSimulator.SimRuntime.iOS-26-5`). Keep the leading `.` in
`endswith`, or another platform's runtime with the same digits would match.
`bootstatus -b` boots the device when it is not booted and returns once it
is, so the install never races the boot. The `.app` is taken from the
scheme's **application** target on the simulator platform, not from the last
block `-showBuildSettings` prints — with an extension in the scheme, the last
block is the extension's, and its `.appex` is not what gets installed. Two
application targets in one scheme: the first is taken, and the file says so
in the report.

Show both commands to the user. Then **run the Build Command once**, here,
before writing anything. It has to exit 0: a configuration whose build was
never seen to pass is a guess with a file name. When it fails, the choice
that failed is what gets revisited — not the file written with a note.
Running the Run Command as well is the user's call; offer it, and when it
runs, confirm the booted device's OS is the one configured
(`xcrun simctl list devices | grep Booted`) — a mismatch means the resolution
picked the wrong device.

**6. Write the file.**

```bash
mkdir -p "$(git rev-parse --show-toplevel)/.hq"
```

Then write `.hq/xcodebuild-config.md` at the repository root — the root, not
the current directory, so a shell opened in a subdirectory writes to the same
place — with this body, the placeholders replaced by the settled values and
the two commands copied exactly as they were run:

````
# xcodebuild-config

| Key               | Value                       |
|-------------------|-----------------------------|
| Project           | <workspace or project file> |
| Scheme            | <scheme>                    |
| Simulator         | <device name>               |
| OS                | <version>                   |
| Deployment Target | <deployment target>         |
| Bundle Identifier | <bundle identifier>         |

## Build Command

```
<the Build Command>
```

## Run Command

```
<the Run Command>
```
````

The two headings and the one fence under each are what `hq:plan` reads;
keep them as they are.

**7. Report.**

- the file's path, and that it is a tracked file: committing it is the user's
  to do, now or with the next change
- the choices made, and the suggestions not taken
- the Build Command's exit code, and whether the Run Command was run
- what was left unsettled — a runtime to download, a scheme the user could not
  decide on

**Layer 2 does not reach this module** — it launches no subagent, so nothing
injects the repository's own notes. Read `.hq/knowledge.md` if this repository
has one.
