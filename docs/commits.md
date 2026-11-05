# Commits

## What a commit holds

- **One purpose,** which one honest title covers. A change one title can't cover is split, and the commits are
  ordered so each builds on the one before it.
- **A whole change.** Each commit builds and passes the project's fast gate on its own, and carries what the change
  makes false elsewhere: the documentation and the status it affects, and a version's declaration with the
  changelog or history entry it opens.

## The message

A message follows [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/),
`type(scope): description`, and describes the change the commit introduces: the repository after the commit, never
the work that produced it.

| Type | A change to |
| --- | --- |
| `feat` | What the project can do |
| `fix` | Behavior that was wrong |
| `perf` | Speed or memory, keeping the behavior |
| `refactor` | The code's structure, keeping the behavior |
| `docs` | Documentation alone |
| `test` | Tests alone |
| `build` | The build, its scripts and its dependencies |
| `ci` | The workflows |
| `chore` | Upkeep the other types leave, such as a release's version |
| `revert` | An earlier commit, undone |

- **The scope** names the area the change belongs to, in the project's own vocabulary, and is left out where the
  change spans the project.
- **The title** summarizes the whole commit and its body in under 50 characters, beginning in lowercase, in the
  imperative, without a closing period.
- **A body** follows a blank line only where the title alone isn't enough, wrapped at 72 characters. It may expand
  the title and stays inside the one change the title names. It states rationale only where the change can't be
  understood correctly without it, and the implementation only where the implementation is the change's subject.
- **A break** of the public contract, from the project's first release on, takes `!` after the type or the scope,
  and a `BREAKING CHANGE:` footer saying what breaks and how to migrate.
- **A message leaves out** the attempts, discoveries and discussion behind the change, lists of files or members,
  test counts, build output and other routine verification, and every attribution trailer, such as
  `Co-Authored-By`.
