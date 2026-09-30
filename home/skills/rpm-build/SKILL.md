---
name: rpm-build
description: Author an RPM spec file and run the full build workflow for a CasjaysDev package — own binaries (Go/Rust), own scripts, own services, and third-party repackaging. Generates spec file, Docker build command, signing steps, and createrepo_c invocation.
---

Use the Codex custom agent `rpm_builder` to build the RPM for the target.
