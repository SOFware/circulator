# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.12] - 2026-02-17

### Added

- Named test sampler classes for reuse across test files (b6bcb4e)
- bang method variants for flow actions (673d8a0)
- Circulator::InvalidTransition exception class (673d8a0)
- host-namespaced InvalidTransition subclass per class with flows (673d8a0)
- flow! instance method and variant: keyword on flow (673d8a0)
- FLOW_VARIANTS registry that drives method definition (673d8a0)

### Changed

- Flow attribute writers are private after flow definition Version: minor (35ea18f)
