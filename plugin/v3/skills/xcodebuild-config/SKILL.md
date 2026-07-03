---
name: xcodebuild-config
description: Used when building and running with xcodebuild. Reads config from .hq/xcodebuild-config.md if it exists, otherwise runs interactive setup.
---

## Context

- Existing config: !`cat .hq/xcodebuild-config.md 2>/dev/null || echo "none"`
- Xcode version: !`xcodebuild -version | head -1`
- Project/Workspace files: !`ls -1 *.xcodeproj *.xcworkspace 2>/dev/null || echo "none found"`
- Available schemes: !`xcodebuild -list 2>/dev/null || echo "failed to list"`

## Instructions

### Phase 0 — Check Existing Config

1. If `.hq/xcodebuild-config.md` exists, read the Build Command and Run Command from it and use that configuration. **Skip to Phase 5 step 5** (optionally verify).
2. If it does not exist, proceed with the setup flow below.

### Phase 1 — Detect Project Settings

1. Identify the project file (`.xcodeproj` or `.xcworkspace`). If both exist, prefer `.xcworkspace`.
2. Detect the deployment target:
   - Check `Package.swift` for `.iOS(.vXX)` platform declaration
   - Or extract `IPHONEOS_DEPLOYMENT_TARGET` from the project's build settings:
     ```
     xcodebuild -showBuildSettings -project <proj> -scheme <scheme> 2>/dev/null | grep IPHONEOS_DEPLOYMENT_TARGET
     ```
3. Detect the bundle identifier:
   - Extract `PRODUCT_BUNDLE_IDENTIFIER` from the project's build settings:
     ```
     xcodebuild -showBuildSettings -project <proj> -scheme <scheme> 2>/dev/null | grep PRODUCT_BUNDLE_IDENTIFIER
     ```
4. Report what was found and proceed.

### Phase 2 — List Available Simulators

1. Fetch all available iOS simulator runtimes and devices:
   ```
   xcrun simctl list devices available -j
   ```
2. Filter runtimes to those **>= deployment target**.
3. Present the user with a numbered list of available **OS versions** (e.g., `iOS 16.0`, `iOS 16.4`, `iOS 17.5`, ...).
4. Ask the user to pick one. Suggest the **minimum OS version** as default (matches deployment target, catches compatibility issues early).

### Phase 3 — Select Device

1. For the chosen OS version, list available devices grouped by type:
   - **iPhone** devices sorted by screen size (smallest first)
   - **iPad** devices sorted by screen size (smallest first)
2. Present as a numbered list.
3. Ask the user to pick one. Suggest the **smallest iPhone** as default.

### Phase 4 — Select Scheme

1. If only one scheme exists, use it automatically.
2. If multiple schemes exist, present them and ask the user to pick one.

### Phase 5 — Generate & Save

1. Build the xcodebuild command:
   ```
   xcodebuild build -<project|workspace> <file> -scheme <scheme> -destination 'platform=iOS Simulator,name=<device>,OS=<version>'
   ```
2. Build the run command sequence (boot simulator, install app, launch):
   ```
   xcrun simctl boot '<device name>'
   open -a Simulator
   xcrun simctl install '<device name>' <path to .app in DerivedData>
   xcrun simctl launch '<device name>' <bundle identifier>
   ```
   - The .app path is typically: `~/Library/Developer/Xcode/DerivedData/<project>-*/Build/Products/Debug-iphonesimulator/<scheme>.app`
   - If the exact DerivedData path is uncertain, detect it from build settings: `xcodebuild -showBuildSettings ... | grep BUILT_PRODUCTS_DIR`
3. Show the generated commands to the user.
4. Save the configuration to `.hq/xcodebuild-config.md`:

   ```markdown
   # xcodebuild-config

   | Key               | Value                          |
   |-------------------|--------------------------------|
   | Project           | <project or workspace file>    |
   | Scheme            | <scheme>                       |
   | Destination       | <full destination string>      |
   | Simulator         | <device name>                  |
   | OS                | <version>                      |
   | Deployment Target | <deployment target>            |
   | Bundle Identifier | <bundle identifier>            |

   ## Build Command

   \`\`\`
   <full xcodebuild command>
   \`\`\`

   ## Run Command

   \`\`\`
   xcrun simctl boot '<device name>'
   open -a Simulator
   xcrun simctl install '<device name>' <path to .app>
   xcrun simctl launch '<device name>' <bundle identifier>
   \`\`\`
   ```

5. Optionally run a test build to verify the command works if the user requests it.

## Rules

- Always use `name=` and `OS=` in the destination string — never use `id=` (UDIDs break when simulators are recreated).
- If no simulators are available for the deployment target OS, warn the user and suggest installing the runtime via `xcodebuild -downloadPlatform iOS`.
- Do not modify any project files — this skill is read-only.
- Keep interactions concise. Use numbered lists for selection, accept numbers as input.
