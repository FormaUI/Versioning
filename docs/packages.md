# Packages

What a project's packages hold, how they declare their dependencies and their metadata, how they're verified, and how
consumers receive them, on npm and on NuGet. How a commit becomes a release, and the step that publishes its packages,
are in [releases](releases.md).

## Identity

- **A package has one id,** which it keeps once published. A package published under a new id is a new package, and
  the one it replaces is deprecated, naming it.
- **Every package a release publishes carries the release's package version,** as the
  [version rules](versions.md#what-carries-a-version) set out.

## Contents

- **A package holds what a consumer needs to use it:** its runtime files, the declarations a consumer compiles or
  type-checks against, the resources it loads as it runs, such as scripts, stylesheets and locale files, its README,
  and its license and notice.
- **A package holds nothing else.** The repository's tests and tooling, build output that belongs to another package,
  and every credential stay out of it.
- **A file is in a package because the project names it,** so a file added to the repository joins a package only
  when the project means it to.

## Dependencies

- **A package declares every package it needs at run time,** each with the lowest version it works with. What only its
  build or its tests use stays undeclared to consumers.
- **A dependency on another package of the same project names the same release's version:** exactly, while the release
  is a pre-release, since pre-releases may break each other, and as its lowest version from the stable release on. A
  consumer installing one package of a release then resolves the others to that release, or to a later compatible
  one.
- **A dependency the consumer's host supplies,** such as a framework the consumer already runs, is declared as one the
  consumer provides.

## Metadata

Every package carries what it is, under what license, where its source is and which commit it was built from, and
where its documentation and its release notes are.

| | npm | NuGet |
| --- | --- | --- |
| What it is | `description` | `Description` |
| Its license, as an SPDX expression | `license` | `PackageLicenseExpression` |
| Its source repository | `repository` | `RepositoryUrl`, published with `PublishRepositoryUrl` |
| The commit it was built from | The provenance attestation trusted publishing records | `RepositoryCommit`, which Source Link sets |
| Its documentation | `homepage`, and the README the package holds | `PackageProjectUrl`, and the README `PackageReadmeFile` names |
| Its release notes | The README's link to the changelog | `PackageReleaseNotes`, linking to the release's changelog entry at its tag |

## Verification

A release's packages are verified as consumers receive them. A repository whose build and tests pass has verified its
sources, and the packages it packs are verified on their own:

- **Each package's files match the list the project keeps of them,** so a missing script, stylesheet, locale file,
  declaration or resource fails, and so does a file the package shouldn't hold.
- **Each package installs into a consumer outside the source checkout,** from a local feed holding the release's
  packages, and the consumer builds where the ecosystem builds and runs a representative use of every package.
- **Each package's declared dependencies resolve** from that feed and the public registries, with nothing the source
  checkout supplies.
- **From the first stable release on, each package's public API stays compatible** with the release before it, where
  the ecosystem's tools check it.

The full gate runs the verification on the packages it builds, and those are the packages the release
[publishes](releases.md#publication).

## Publication

- **A package is published to its ecosystem's public registry,** the npm registry or nuget.org, and to any other feed
  the project states for it.
- **A pre-release never becomes the default install.** A consumer installs one only by asking for it: by its version,
  or by its stage's channel where the ecosystem has channels.
- **Packages publish in dependency order,** each package after the packages of the release it depends on, so a
  consumer never finds a package whose dependency of the same release is missing. A release is published once every
  package is on every feed, and a publication that stops partway [runs again](releases.md#publication).

## npm

- `files` lists what the package holds, and `exports` and `types` what a consumer imports and type-checks against.
- `dependencies` holds what the package needs at run time, `peerDependencies` what the consumer's host supplies, and
  `devDependencies` what its build and tests use. A dependency on a package of the same project is `X.Y.Z-preview.N`
  exactly under a pre-release, and `^X.Y.Z` from the stable release on.
- A stable release is published under the `latest` dist-tag, and a pre-release under the dist-tag named for its
  stage, `preview` or `rc`.
- `npm pack` writes the tarball the verification installs, and publication publishes that tarball.
- A version consumers should leave is deprecated with `npm deprecate`, and stays published.

## NuGet

- A project's references become its package's dependencies, and a reference used only to build is kept from
  consumers with `PrivateAssets="all"`. A dependency on a package of the same project is `[X.Y.Z-preview.N]` exactly
  under a pre-release, and `X.Y.Z` as its lowest version from the stable release on.
- A pre-release installs only when a consumer asks for one by its version, so it never becomes the default.
- Source Link is on, with `PublishRepositoryUrl` and `ContinuousIntegrationBuild` set for the build that packs, and a
  package that holds assemblies publishes its symbols beside it, as a `.snupkg`.
- Package validation, `EnablePackageValidation`, checks each package's assemblies across its targets, and from the
  first stable release on, against the release before it through `PackageValidationBaselineVersion`.
- A version consumers should leave is deprecated, naming its replacement where it has one, and unlisted.
