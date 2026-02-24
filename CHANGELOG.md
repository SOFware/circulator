# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.13] - 2026-02-24

### Added

- Flow#dup_for method for deep-copying flows to subclasses (4f75b79)
- Error on redeclaring inherited flow attributes in subclasses (98ca6a7)
- Extension support for subclasses that inherit parent flows (d73f231)
- Lazy application of pending extensions via inherited hook (2ed2787)

### Changed

- Subclasses of Circulator classes inherit parent flows Version: major (2a63539)
- Flow methods use dynamic transition lookup for inherited flows (2ed2787)
