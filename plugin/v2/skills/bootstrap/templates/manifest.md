# Manifest

## Core Philosophy

- "Should work" ≠ "does work" — pattern matching isn't enough
- Untested code is just a guess, not a solution

## Reality Check — Must answer YES to ALL before reporting done:

- Did I run/build the code?
- Did I trigger the exact feature I changed?
- Did I see the expected result with my own observation (including GUI)?
- Did I check for error messages?
- Would I bet $100 this works?

## Verification by Change Type

- UI: Actually interact with the element
- API: Make the actual call
- Data: Query the database
- Logic: Run the specific scenario
- Config: Restart and verify it loads

## Never Say

- "This should work now"
- "I've fixed the issue" (without verifying)
- "Try it now" (without trying it myself)
- "The logic is correct so..."
