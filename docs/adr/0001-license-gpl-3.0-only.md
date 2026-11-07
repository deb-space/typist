# ADR 0001: GPL-3.0-only with a proxy for later versions

- **Status:** accepted
- **Date:** 2026-11-07

## Context

Typist is free and open source and competes with paid dictation and meeting apps. We want any product built on Typist's code to stay open source, so that paid competitors cannot build closed products on top of our work.

## Decision

- Typist is licensed under **GPL-3.0-only**, with the option to use a later version of the GPL that **deb-space approves**, acting as a proxy as defined in Section 14 of GPL-3.0. This is the same approach KDE uses.
- We do not use "GPL-3.0-or-later". That would automatically allow any future GPL version, whose terms we do not know yet.
- `LICENSE` contains the unmodified GPL-3.0 text. `COPYING` contains the license notice with the proxy clause.
- Every source file has the SPDX header `GPL-3.0-only`. CI checks it.
- Contributions use the Developer Certificate of Origin (`Signed-off-by`), not a CLA. Contributors keep their copyright.
- Dependencies must be GPL-3.0 compatible (MIT, BSD, Apache-2.0 and similar). GPL-2.0-only and proprietary SDKs are not allowed. All dependencies are listed in `THIRD_PARTY_NOTICES.md`.

## Consequences

- Distributed modified versions of Typist must stay open under GPL-3.0.
- Without a CLA, the project cannot be relicensed under a non-GPL license later without the agreement of all contributors. This is intended.
- Moving to a future GPL version requires an explicit decision by deb-space.
