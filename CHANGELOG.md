# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2025-03-12

### Changed

 - Lower the general logging level and prevent crash logs by using shutdown error
reasons.

### Fixed

- Fix a JSON preprocess bug with boolean values.

## [1.0.1] - 2025-02-26

Cleanup TLS options in debug log

## [1.0.0] - 2025-02-25

Jsonrpc 2.0 connection handling:
- gun 2.1.0 websocket connection handling
- jsonrpc 2.0 codec


[Unreleased]: https://github.com/grisp/jarl/compare/1.1.0...HEAD
[1.1.0]: https://github.com/grisp/jarl/compare/1.0.1...1.1.0
[1.0.1]: https://github.com/grisp/jarl/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/grisp/jarl/compare/a89954b6be9c0e929a168f2fb7d67dafaae1f349...1.0.0
