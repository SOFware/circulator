# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.4] - 2025-11-03

### Added

- Symbol-based allow_if support (a96b794)
- Documentation for symbol-based allow_if (d3befc1)
- available_flows method with guard and argument support (122e2ab)
- available_flow? predicate method (122e2ab)
- Documentation for query methods (a75507e)

### Changed

- Validate symbol allow_if at definition time (392eac5)

### Removed

- Redundant respond_to? check (40ff669)

### Fixed

- DOT syntax error for states ending with ? (65b503e)
