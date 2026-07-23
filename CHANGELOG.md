# Changelog

All notable changes to TRENDYtoILAMB.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-07-01

### Added
- TRENDY v14 / S2 support: retargeted single-model and bulk example scripts.
- Detection of bare decimal-year monthly time (e.g. ELM-FATES: `1701.0, 1701.0833, …`)
  when a file has no usable CF `units`; previously these were misread as
  `days since 1850`, collapsing the whole record into ~1854.
- `scripts/parallel_convert_local.sh`: non-SLURM parallel launcher (one worker
  per model, capped concurrency) for single multi-core nodes.
- Output compression (shuffle + deflate) on the main variable (~5x smaller files).
- Configurable simulation subdirectory and filename date range in the model
  worker via `SIM` / `OVERRIDE_START` / `OVERRIDE_END` env vars.
- Registry metadata for `hfls`, `hfss`, `rlds`, `rlus`, `rsus`, `evspsbl`, `tran`.
- Guard that warns when a converted variable is entirely fill/NaN (usually a
  bad/partial write).
- `examples/test_awkward_models.jl` covering months-since / years-since /
  month-index encodings.

### Fixed
- Never emit `units = "unknown"`: for variables without a registry mapping,
  preserve the (standardized) source units so files stay CF-usable. Fixes ILAMB
  `UnitConversionError` (e.g. JSBACH `hfls`, source `W m-2`).
- Derive filename start/end dates from the rebuilt `time_bounds` rather than raw
  CFTime endpoints, fixing `months since` filenames (e.g. CABLE-POP `202503` →
  `202412`).
- Verification no longer crashes on ocean-masked (`missing`) data; the valid
  mask is built element-wise so `missing` is never passed to `Float64`/`isnan`.

## [0.1.0] - 2024-10-18

### Added
- Initial release of TRENDYtoILAMB.jl
- Core conversion functionality from TRENDY to ILAMB format
- Support for 19 ILAMB variables (carbon fluxes, hydrology, pools, fire, forcing)
- ILAMB-compliant filename generation: `{var}_Lmon_ENSEMBLE-{model}_historical_r1i1p1f1_gn_{YYYYMM}-{YYYYMM}.nc`
- Multiple time encoding support:
  - Days/months/years since various reference dates
  - Month indices (CARDAMOM-specific)
  - CF-compliant datetime objects with noleap calendars
- Model-specific handlers:
  - CARDAMOM: Month index conversion (1-252 → 200301-202312)
  - CABLE-POP: 1700 reference year handling
  - Generic handler for standard time encodings
- Robust error handling:
  - Safe attribute access with fallback defaults
  - NetCDF file validation before conversion
  - Detailed error reporting with helpful context
- Data verification:
  - Built-in comparison between input and output
  - Floating-point tolerance checking
  - Metadata preservation validation
- Batch conversion script for all TRENDY models
- Comprehensive statistics tracking during conversion
- Example scripts for testing and quick validation

### Fixed
- Time conversion for models with different reference years (1700, 1850, etc.)
- CARDAMOM date range extraction from month indices
- CABLE-POP date handling with 1700-based reference
- Attribute access errors for files with missing metadata
- Time bounds dimension ordering (handles both 2×n and n×2)

### Changed
- Output directory structure: Models output directly to `{MODEL}/` folders (removed S3 subdirectory level)
- Default output location: `/home/renatob/data/ilamb_ready/` (configurable)
- Time standardization: All outputs use `days since 1850-01-01` with `noleap` calendar

### Technical Details
- Julia v1.9+ compatibility
- NCDatasets.jl v0.12 for NetCDF handling
- CF-compliant time representation
- Memory-efficient processing for large files
- Supports TRENDY v13 dataset (22 models, ~840+ files)

## [Unreleased]

### Planned
- Add unit tests for core functionality
- Support for additional ILAMB variables
- Performance optimizations for very large grids
- Parallel processing for batch conversions
- Integration with ILAMB workflows
- Documentation website with detailed examples
