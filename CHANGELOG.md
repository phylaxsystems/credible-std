# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2025-01-22

### Added

- **Single Transaction Backtesting**: New `executeBacktestForTransaction()` function to test a specific transaction by hash
- **Automatic Internal Call Detection**: Block range backtesting now automatically detects internal/nested calls to the target contract using trace APIs with smart fallback:
  - `trace_filter` (fastest, requires Erigon/archive node)
  - `debug_traceBlockByNumber` (slower but widely supported)
  - `debug_traceTransaction` (slowest, per-transaction tracing)
  - Direct calls only (fallback when no trace APIs available)
- **Auto-detect Script Path**: The `transaction_fetcher.sh` script path is now automatically discovered - no need to set `CREDIBLE_STD_PATH` manually
- **Trace Replay for Failed Assertions**: Failed assertions now show full Foundry execution trace for debugging
- **Improved Logging**: Clear feedback about detection method and fallback status

### Changed

- **BREAKING**: Removed `useTraceFilter` from `BacktestingConfig` struct - trace detection is now automatic with fallback

### Fixed

- Panic error decoding now shows human-readable messages (e.g., "Panic: array out-of-bounds access")
- Parsing when zero transactions are found in block range
- Whitespace trimming in data extraction
- `set -e` no longer blocks trace method fallback in bash script

## [0.3.0] - 2025-01-15

### Added

- Initial backtesting framework with block range support
- `CredibleTestWithBacktesting` base contract
- Transaction fetcher bash script with trace_filter support

## [0.2.0] - 2025-01-10

### Added

- Core assertion framework
- `CredibleTest` base contract
- PhEvm cheatcodes integration

## [0.1.0] - 2025-01-05

### Added

- Initial release
- Basic project structure
