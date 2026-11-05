# Branches

A project has three permanent branches, and every other branch is a fix branch or a feature branch.

| Branch | What it holds |
| --- | --- |
| `dev` | The integrated work. Every change lands here first. |
| `candidate` | The candidate, the commit of `dev` selected for release, under its full gate. |
| `main` | The latest release. It's the default branch, and it advances only by [promotion](releases.md#promotion). |

## Landing work

- A change lands on `dev`, directly or by a pull request from a branch of its own, branched from `dev` and named
  for what it delivers:
  - `fix/<name>` for a correction of behavior that's wrong, which is what a `fix` commit carries;
  - `feature/<name>` for every other change.
- A pull request into `dev` lands by fast-forward: its branch is rebased onto `dev`, and `dev` advances to its head
  commit, `git push origin <branch>:dev`, which marks the pull request merged.
- Every commit on a permanent branch carries a verified signature. A rebase signs the commits it rewrites with the
  key of whoever rebases them.
- A push to `dev`, to a fix branch or to a feature branch, and a pull request into `dev`, runs the project's fast
  gate, or its full gate where the project has one gate.
- `candidate` and `main` only ever fast-forward. Neither takes a commit of its own, a merge commit, a force push or
  a deletion.
- The rules that keep a permanent branch's history, its signatures, its linear history and the bans on force pushes
  and deletion, bind everyone. The maintainer may push past only the rule that work reaches `dev` and `main`
  through a pull request.

## Stabilizing a candidate

A project stabilizes one candidate at a time, and every release comes from `dev`'s history, so `main` always holds
the newest release.

1. Stabilization begins: merges into `dev` unrelated to the release pause, and other work goes on in its
   branches.
2. `dev`'s tip becomes the candidate: its SHA is recorded, `candidate` fast-forwards to it, and the full gate runs on
   that SHA. Selecting the tip leaves no unrelated work between the candidate and a later fix.
3. A fix for the candidate lands on `dev`, from a fix branch or directly, the one merge the pause admits, and the
   corrected tip goes to `candidate` for a fresh full run.
4. The release's version and its changelog entry's date are set on `dev` before the final run, so the commit that
   passes is the one `main` receives and the release's tag names.
5. Once `main` holds the release, merges into `dev` resume.

A stabilization the maintainer calls off resumes merges into `dev` too, and the next candidate moves `candidate`
forward from the commit it holds.
