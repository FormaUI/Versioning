# Changelog

Each release of Versioning, newest first. An entry is dated when its release is cut, and reads *Unreleased* until
then.

## `1.0.0-preview.3`

*November 5, 2026*

- The release check accepts a release tag whose signature GitHub verifies, so the maintainer signs with any key
  their GitHub account holds. It refuses a tag whose tagger email the signing account hasn't verified, so a
  release is tagged under an email that account has verified.

## `1.0.0-preview.2`

*November 5, 2026*

- `actions/publish-packages` publishes a release's saved packages to a feed in dependency order, past what the feed
  already holds.
- The promotion check tells a pull request into `main` from anywhere but `candidate` to target `dev`.

## `1.0.0-preview.1`

*November 5, 2026*

- The rules every FormaUI project follows for its versions, its branches, its commits, its releases and its packages.
- The promotion check, the release check and the step that attaches a release's packages, as GitHub Actions a
  project's workflows call.
