# Verification

A change is checked as it's made, by the narrowest check that can show it wrong, and checked whole before it lands.
The checks cost what they must and no more: none repeats work another has done, and none is weakened to save time.

## The gates

- **The fast gate** builds what the unit and component suites need once, runs them on that build, and runs the
  project's other quick checks, such as its script tests. It returns in minutes, so it runs on every push and pull
  request [Branches](branches.md#landing-work) names.
- **The full gate** runs every check the project has: packaging, integration, and every browser, runtime and
  platform the machine can host, naming each one it can't. It runs on every push to `candidate`, nightly on `dev`,
  and locally where a change reaches what everything else rests on: the build, the hosts, or code every component
  shares.
- **A project states both gates** in its own documentation, and what each one runs.

## While a change is made

- **The narrowest check first.** A change is checked first by the tests of the code it changes, run alone on the
  build already on disk. A suite that shows it wrong is run again alone, never the gate around it.
- **One configuration while iterating.** A check that runs in several runtimes, browsers or platforms runs in one
  while the change is made, and in all of them once the change is otherwise done.
- **A new test helper is proved on one case** before a suite runs on it, since a helper's mistake fails every case
  that uses it.
- **A filtered run builds what its checks read.** A run narrowed to some checks builds, packs and publishes only
  what those checks need, and publishes into the output the last run left, unless a selected check counts what that
  output holds. An unfiltered run builds everything afresh.

## Before a change lands

- **Each commit passes the fast gate,** as [Commits](commits.md#what-a-commit-holds) asks. A change split into
  commits runs its wider checks once, on its final state: the browser checks for what it touches, the format
  check, and the full gate where its reach calls for it.
- **A change to a check proves the check still fails where it must:** the failure it exists to catch is planted,
  and the check is seen to catch it.

## Keeping the checks fast

- **No step repeats another's work.** The tests run on the build the gate has just made, and a check holding what
  the build already enforces is cut to what it adds, as a formatting check left to the text no compiler reports.
- **Independent work runs side by side.** Tests stand in classes named for their subjects, which run in parallel,
  and the independent cases of a check run together; a test that needs the machine to itself says so.
- **Every step records its time,** and a change to the gate is measured step by step before and after it. What to
  speed up is read from those records, the longest step first.

## Keeping the checks true

- **No check is weakened to save time.** Coverage is never traded for speed; only work done twice, or work no
  selected check reads, is left out.
- **A test that fails under load is a bug,** in the test or in the code, never noise. A test waits on the
  completion it controls, never on the clock, and a fix is proved by repeating the test while something else loads
  the machine. A retry or a widened timeout hides the failure rather than removing it.
- **A failure is reproduced before it's fixed,** in the narrowest run that shows it.
