# SA Flutter (SAF)

Before doing anything in this project, read `docs/PLAN.md`: it holds the agreed decisions, the stage plan, current status
and the test log. Update its Status and Test log sections at the end of each stage, and commit at the end of each stage.

David's working style: he often says "don't change code yet" - then explain only. He expects root causes before fixes,
precise verified answers, and risks flagged. He builds and runs everything himself (Claude cannot build or run Flutter apps here;
it can run `dart analyze` with Dart 3.13.7 + a sparse Flutter stable checkout, and draw assets/score/ in Chromium),
so give exact Terminal commands. Keep platform-specific code inside `lib/platform/`.
