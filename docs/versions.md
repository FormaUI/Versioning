# Versions

Every version is a [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) version, and each release's
version is higher, by SemVer's precedence, than the version of every release before it.

## What carries a version

- **The package version** is the version of a project's release. Every package the project publishes carries it,
  and the release's tag names it.
- **A contract version** is the version of a specification or a language the project defines. It moves
  independently of the package version: a release records the contract versions it implements, and a release that
  fixes only the implementation advances the package version and keeps the contract versions it had. A contract
  version is released with the release that records it, under that release's tag.
- **Each version has one declaration,** the one place in the project's sources that states it. Everything else
  that names the version repeats it from there: the package metadata the build writes, the changelog and the
  histories, and a link to a past release.

## Stages

A major version, `X.0.0`, passes through three stages, and each stage's promise covers the project's public
contract.

| Stage | Version | Promise |
| --- | --- | --- |
| Preview | `X.0.0-preview.N` | The contract can change from one preview to the next, and a change that breaks what the release before it allowed says how to migrate |
| Release candidate | `X.0.0-rc.N` | The contract is frozen: a release candidate changes only by compatible fixes, and nothing breaks the contract before the next major version |
| Stable | `X.0.0` | Semantic Versioning's promise: a patch release fixes compatibly, a minor release adds compatibly, and only a major release breaks |

- **The first release of a major version** is preceded by at least one preview and one release candidate.
- **A minor or a patch release** is published stable directly, or after previews or release candidates of its own,
  `X.Y.0-preview.N` or `X.Y.Z-rc.N`, where its changes are worth trying first. Those change only what the release
  adds, and keep everything the stable releases before it promise.
- **A pre-release identifier** is `preview.N` or `rc.N`, numbered from 1, with a dot before the number, so
  `preview.10` follows `preview.9`.
- **A compatible fix** brings the implementation to what the contract states. A change to what the contract states
  is a change to the contract, whatever it corrects.

## The public contract

A project states its public contract in its own documentation, and the stages' promises cover what it states:

- for a package, its public API: the types, members and behavior a consumer reaches;
- for a specification or a language, its syntax and its semantics;
- for a file format, a protocol or a command line a consumer depends on, that format, protocol or command line.

## Advancing a version

- **The declared package version is the version the next release carries.**
- **After a release,** the first change a consumer can notice advances the declaration and opens the changelog's
  next entry, in the same commit.
- **The declaration advances by the smallest step that change requires:**
  - from `X.Y.Z-preview.N` to `X.Y.Z-preview.N+1`, for any change the preview's promise allows;
  - from `X.Y.Z-rc.N` to `X.Y.Z-rc.N+1`, for a compatible fix, the one change a release candidate takes;
  - from a stable `X.Y.Z` to `X.Y.Z+1` for a fix, to `X.Y+1.0` for an addition, or `X.Y+1.0-preview.1` where it's
    tried first, and to `X+1.0.0-preview.1` for a break.
- **The declaration is provisional until the release.** A later change that requires a larger step raises it, as an
  addition after a fix raises `X.Y.Z+1` to `X.Y+1.0`.
- **Leaving a stage is the maintainer's decision,** made when the contract is ready and set in the declaration: the
  last preview, `X.0.0-preview.N`, is followed by `X.0.0-rc.1`, and the last release candidate by `X.0.0`.
- **A contract version advances when its contract changes, or when the maintainer moves it to its next stage.** The
  first change to the contract after a release advances its declaration and opens the next entry of its history, in
  the same commit, and each later change before the next release joins that entry. Moving a frozen contract from
  `X.0.0-rc.N` to `X.0.0` changes only its version, and its history entry says so. A contract version advances by
  the same stages and steps as the package version.
