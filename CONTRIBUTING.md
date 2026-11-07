# Contributing to Typist

Thanks for your interest. Typist is at an early stage, so before starting on a large change, please open an issue to discuss it.

## Ground rules

- **Privacy first.** Typist sends nothing off the device unless the user has configured an external endpoint. Telemetry, analytics and crash reporters that phone home will not be accepted.
- **Our own code.** Do not copy or adapt code from other dictation or meeting apps, including open-source ones. Looking at how other products behave is fine. Copying their code is not.
- **Dependencies** must be compatible with GPL-3.0 (for example MIT, BSD or Apache-2.0). GPL-2.0-only and proprietary SDKs cannot be used. Add every new dependency to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) in the same pull request.

## License headers

Every source file starts with an SPDX header:

```swift
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors
```

Use the comment syntax of the file's language (`#` for shell, YAML and Makefiles, `<!-- -->` for plists). `scripts/check-spdx.sh` checks this in CI.

Contributors keep the copyright to their contributions. By submitting them, you license them under the terms in [COPYING](COPYING).

## Before opening a pull request

```sh
make format
make check   # lint, tests, SPDX headers
make app     # if you touched App/ or project.yml
```

Keep pull requests focused on one change, and describe what you tested, especially on which macOS versions.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
