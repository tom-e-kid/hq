Notes for agents working in this repository. Everything here is what the
repository's own documents do not say; what they do say is not repeated.

**The plan carries the survey, not the design.** `## Notes` was written against
a survey of this repository, so what the change reaches is already answered —
do not survey the tree again to find it. The design is a different question and
it is yours: before settling one, read `git log` over the area you are about to
touch and the code those commits landed, because this tree's idiom moves. Once
the design is settled, the fence files and their adjacent tests are enough
reading to work an item. On a fix pass the files a directive names, and their
adjacent tests, are the reading, and nothing is redesigned.

**The canon is consulted by section.** `docs/design.md` is the design canon;
read the section an item touches, not the file. One section binds every script
change whatever the item says: § 設計原則 — the bash the scripts must run on,
the test file every script carries, what a fixture has to cover. Read that
section before touching `plugin/scripts`. The test suite enforces most of it,
but at the end of the pass, not while you write.

**Nothing in this tree is frozen.** There is one plugin directory and no
archived versions of it, so a path that looks like an old copy is not one —
open it and read it like anything else.
