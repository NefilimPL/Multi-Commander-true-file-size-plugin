# Release Build and Error Handling Design

## Goal

Make MCRealDiskSize releases produce installable DLL packages from GitHub Release tags, prefer available self-hosted Windows runners, fall back to GitHub-hosted runners when needed, and avoid showing raw `ERROR` values for transient data-loading failures.

## Current State

- The plugin is a Visual Studio 2022 C++ DLL project.
- Local builds use `scripts/02_build.ps1`, which downloads the Multi Commander SDK if missing and builds `MCRealDiskSize.vcxproj`.
- The plugin version is currently hard-coded in `src/MCRealDiskSizeProp.cpp`.
- There is no GitHub Actions workflow.
- `GetCloudStatusText()` returns `ERROR` when Windows attributes cannot be read.
- Size columns return `ERR:<code>` when allocated-size reads fail.

## Release Trigger

Release builds should run when a GitHub Release is published and when a matching version tag is pushed.

Accepted tags:

- `V1.0.0`
- `v1.0.0`
- `V1.0.0.1`
- `v1.0.0.1`

The plugin version is the tag without the leading `V` or `v`. The version must have three or four numeric parts. Invalid tags fail early with a clear workflow error.

Release notes describe compatible Multi Commander versions. The workflow does not need to parse compatibility from prose for build decisions in this iteration. The README will document the expected release-note format so users can read compatibility from the release description.

## Runner Selection

Runner selection is two-stage:

1. A lightweight preflight job runs on `ubuntu-latest`.
2. It checks repository self-hosted runners through the GitHub REST API and selects:
   - `["self-hosted","Windows","X64"]` when an online, non-busy runner with these labels exists.
   - `"windows-latest"` otherwise.

The current repository runners use labels `self-hosted`, `Windows`, and `X64`. This keeps the workflow future-proof when more compatible runners are added.

The preflight should use an optional secret named `RUNNER_STATUS_TOKEN` for API access. If the secret is missing, the workflow cannot verify runner availability and should use the self-hosted labels by default. If the secret is configured but no online non-busy self-hosted runner is found, or the API call fails, the workflow must fall back to `windows-latest`.

## Artifact Policy

There are two different outputs:

- Release asset ZIP: the installable package attached to the GitHub Release.
- GitHub Actions artifact: a workflow artifact uploaded through `actions/upload-artifact`.

Rules:

- When the build runs on a self-hosted runner, create and upload the release asset ZIP, but do not upload an Actions artifact.
- When the build falls back to `windows-latest`, create and upload the release asset ZIP and also upload an Actions artifact.

This keeps self-hosted releases clean while still preserving fallback build outputs in Actions.

## Package Layout

Each ZIP should contain an install-ready plugin folder:

```text
MCRealDiskSize/
  MCRealDiskSize.dll
```

ZIP file name:

```text
MCRealDiskSize-v<plugin-version>-<platform>.zip
```

Examples:

- `MCRealDiskSize-v1.0.0-x64.zip`
- `MCRealDiskSize-v1.0.0.1-x64.zip`

The first workflow implementation should build and publish only `x64 Release`. The scripts can stay compatible with `Win32`, but CI release packaging excludes Win32 from this scope.

## Version Injection

The C++ source should not require manual edits for every release. Add a project-level preprocessor definition, for example:

```text
MCREALDISKSIZE_VERSION="1.0.0"
```

`GetExtensionInfo()` should use that macro. Local builds without the macro should keep a sensible development default, such as the current `0.1.2.0`.

The release build script should pass the version derived from the tag into MSBuild.

## Error Display

The plugin should stop showing raw `ERROR` and `ERR:<code>` text for normal transient read failures.

Desired behavior:

- Status column:
  - If attributes cannot be read, return `UNKNOWN` instead of `ERROR`.
- Size columns:
  - If calculation is cancelled, return no value so Multi Commander can retry or clear the async value.
  - If a path cannot be read because it disappeared or is temporarily inaccessible, return no value instead of `ERR:<code>`.

The implementation should still keep enough structure for future diagnostics. A small helper for classifying Windows error codes is acceptable, but no logging system is required in this iteration.

## Build Scripts

Add a packaging script that:

- Accepts `Version`, `Platform`, and `Configuration`.
- Validates the version format.
- Builds through `scripts/02_build.ps1`.
- Stages `MCRealDiskSize.dll` under `artifacts/package/MCRealDiskSize/`.
- Creates the ZIP under `artifacts/release/`.
- Emits the ZIP path for GitHub Actions.

Update `scripts/02_build.ps1` so it can pass an optional plugin version to MSBuild.

## Documentation

Update README with:

- Release ZIP installation instructions.
- Expected release-note compatibility format, for example:

```text
Compatibility:
- Multi Commander 15.8
- Windows 10/11 x64
```

- Self-build requirements for creating the DLL:
  - Windows 10/11.
  - Visual Studio 2022 or Build Tools 2022.
  - Workload `Desktop development with C++`.
  - MSVC v143 C++ toolset.
  - Windows 10/11 SDK.
  - PowerShell 5.1 or newer.
  - Internet access for the first SDK download, unless `external/MultiCommander-SDK-main` is already present.

## Testing and Verification

Add focused script tests where possible for tag/version and package naming. For C++ behavior, at minimum verify the project builds. If full unit testing is impractical because the SDK is absent locally, keep the error-handling change small and compile-verified.

Manual verification targets:

- `scripts/02_build.ps1 -Platform x64 -Configuration Release`
- Packaging script with a valid version.
- Packaging script rejects an invalid version.
- Workflow YAML parses structurally.
