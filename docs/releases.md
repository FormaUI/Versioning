# Releases

A release is a candidate that passed its full gate, promoted to `main` and tagged there. Publication is the step
after it: the project's release workflow publishes the tagged commit's packages to the project's feeds. The two are
separate, so a commit stays released when its publication fails, and publication runs again for the same tag.

## Promotion

Promotion is a pull request from `candidate` into `main`. The promotion check runs on it, and a release signer,
approving it, fast-forwards `main` to its head commit, `git push origin candidate:main`, which marks the pull request
merged. `main` then holds the candidate's exact commit, so every commit `main` has advanced to is a release.

The promotion check holds the pull request to:

| Check | Holds when |
| --- | --- |
| Source | The pull request comes from this repository's `candidate` |
| Gate | The project's full-gate workflow passed on the head commit's exact SHA, in a run on a push to `candidate`, in this repository |
| Version | The package version's declaration at the head commit is higher, by precedence, than every release's before it, and every feed lacks it |
| Changelog | The changelog at the head commit holds the version's entry, dated |

## The tag

- A release's tag is named `v` and the package version, as `v1.0.0-preview.1`, and marks the commit `main` was
  promoted to.
- It's annotated, with the project's name and the version as its message, as `Forma 1.0.0-preview.1`, and signed by
  a release signer.
- Only a release signer creates a release tag, and a pushed tag is never moved or deleted.

### Release signers

| Account | Primary key fingerprint |
| --- | --- |
| [soyeyalon](https://github.com/soyeyalon) | `CAFC 1934 0836 6FD4 B53B  48C5 2AFD EA51 2887 E037` |

A tag's signature verifies when Git verifies it and the primary key that made it is one listed here.

## The release check

The release check runs on the tag's push, before anything is published, and holds the release to:

| Check | Holds when |
| --- | --- |
| Tag | Its name is `v` and a version by the [version rules](versions.md), it's annotated, and its signature verifies against a release signer's key |
| Commit | Its commit is the head commit of a merged promotion pull request, and `main` holds it |
| Gate | The project's full-gate workflow passed on that exact SHA, in a run on a push to `candidate`, in this repository |
| Version | The tag's version equals the package version's declaration at the tagged commit |
| Changelog | The changelog at the tagged commit holds the version's entry, dated |

Publication runs only once every check holds, and builds from the tagged commit.

## Publication

- The project's own release workflow publishes, on the tag's push, through each feed's trusted publishing where the
  feed offers it, so each run holds a credential that expires with it.
- A failed publication runs again for the same tag, and publishes what the feeds lack, from the same commit.
- A release's contents are fixed once it's published, and a fix to them is the next version. A published version is
  never deleted: one consumers should leave is deprecated or unlisted, and the next release replaces it.

## The release record

- **The changelog,** `CHANGELOG.md` at the project's root, holds one entry per release, newest first. An entry is
  headed by its version and dated on its release, reading *Unreleased* until then. It names the contract versions
  the release implements and lists every change a consumer can notice, and a change that breaks what the release
  before it allowed says how to migrate.
- **A contract's history** holds one entry per contract version, with what the version changed in the contract,
  what it breaks and how to migrate. A changelog entry names the contract version and links to its history entry,
  leaving the contract's changes to the history.
- **A record kept before a project's first release** stays as that period's archive, and the changelog links to it.
