# Security policy

## Supported versions

Only the latest release of `ruby-blinkstick` gets security fixes. While the
gem is at 0.x, a fix ships as a new patch or minor release.

## Reporting a vulnerability

Please report privately through GitHub:
[Report a vulnerability](https://github.com/bawdo/ruby-blinkstick/security/advisories/new).
Do not open a public issue.

Include what you found, how to reproduce it, and the version, Ruby version
and operating system you used. You can expect an acknowledgement within a
week. Once a fix is released, the advisory is published with credit to you,
unless you would rather stay anonymous.

## Scope

In scope: this gem's code, its published `.gem`, and its release workflow.
Examples are a write to EEPROM from a call that is documented as read only,
or a problem in how releases are built and published.

Out of scope: BlinkStick firmware and hardware, and the HID libraries the gem
will depend on. Report those upstream.

Releases are published from GitHub Actions through rubygems.org trusted
publishing from 0.0.1 onward. A version that rubygems.org does not attribute
to this repository's workflow did not come from it.

From 0.0.2, every release also carries SLSA build provenance, made and
verified by the release workflow before the gem is published. It is attached
to the version on rubygems.org and to the GitHub release. To check that a gem
was built by this repository's release workflow:

```sh
gem fetch ruby-blinkstick -v 0.0.2
gh attestation verify ruby-blinkstick-0.0.2.gem --repo bawdo/ruby-blinkstick
```

The trusted publisher on rubygems.org must keep naming the `rubygems`
environment. The job that makes the attestation can request an OIDC token but
has no environment, so that name is what stops it minting a rubygems.org key.
A publisher recreated without an environment would undo that.
