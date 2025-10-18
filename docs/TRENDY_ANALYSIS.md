# TRENDY Dataset Analysis

Analysis of the TRENDYv13 dataset performed on October 17, 2025.

## Dataset Overview

- **Total Files**: 840 NetCDF files
- **Models**: 16 different land surface models
  - CABLE-POP, CLASSIC, CLM5, DLEM, IBIS, ISAM, JSBACH, JULES
  - LPJ-GUESS, LPJmL, LPJwsl, LPX-Bern, OCN, ORCHIDEE, SDGVM, VISIT
- **Simulations**: S0, S1, S2, S3 (different forcing scenarios)

## Time Representation Analysis

### Time Unit Distribution

Based on analysis of 1,582 variables with time units:

| Time Unit | Count | Percentage | Notes |
|-----------|-------|------------|-------|
| Unknown   | 788   | 49.8%      | Non-standard units (kg m-2 s-1, K, W m-2, etc.) |
| Days      | 555   | 35.1%      | "days since YYYY-MM-DD" |
| Years     | 105   | 6.6%       | "years since YYYY-MM-DD" |
| Months    | 69    | 4.4%       | "months since YYYY-MM-DD" |
| Hours     | 65    | 4.1%       | "hours since YYYY-MM-DD" |

### Reference Dates

Most common reference dates for time units:

**For "days since" format:**
- 1700-01-01: 466 occurrences (84.0%)
- 0001-01-01: 45 occurrences (8.1%)
- 1699-12-31: 40 occurrences (7.2%)
- 1701-01-16: 2 occurrences (0.4%)
- decimal: 1 occurrence (0.2%)
- 1980-01-01: 1 occurrence (0.2%)

**For "years since" format:**
- 0000-01-01: 33 occurrences (31.4%)
- 1700-01-01: 31 occurrences (29.5%)
- unspecified: 19 occurrences (18.1%)
- 1700-06-15: 18 occurrences (17.1%)
- decimal: 4 occurrences (3.8%)

**For "months since" format:**
- 1700-01-16: 30 occurrences (43.5%)
- 1700-01-01: 28 occurrences (40.6%)
- decimal: 11 occurrences (15.9%)

**For "hours since" format:**
- 1700-01-01: 28 occurrences (43.1%)
- 1701-01-16: 26 occurrences (40.0%)
- 1701-07-01: 9 occurrences (13.8%)
- 1900-01-01: 2 occurrences (3.1%)

### Special Time Formats

Some files use non-standard time formats:
- AD format: `"years since AD 1700-Jan-1st"`
  - Encountered in VISIT model files
  - Causes warnings in CommonDataModel package
- Decimal formats: `"year as %Y.%f"`, `"month as %Y%m.%f"`, `"day as %Y%m%d.%f"`

## Variable Analysis

### Most Common Variables

| Variable | Files | Percentage | Data Types |
|----------|-------|------------|------------|
| time | 811 | 96.5% | DateTimeNoLeap, DateTime360Day, Float64, DateTime, Int32 |
| latitude | 502 | 59.8% | Float32, Float64, Union{Missing, Float32/Float64} |
| longitude | 502 | 59.8% | Float32, Float64, Union{Missing, Float32} |
| lat | 333 | 39.6% | Float32, Float64, Union{Missing, Float32} |
| lon | 333 | 39.6% | Float32, Float64, Union{Missing, Float32} |
| bounds_lat | 158 | 18.8% | Float64 |
| bounds_lon | 158 | 18.8% | Float64 |
| time_bounds | 153 | 18.2% | DateTime |
| lon_bnds | 48 | 5.7% | Float64, Union{Missing, Float64} |
| lat_bnds | 48 | 5.7% | Float64, Union{Missing, Float64} |

**Total Unique Variables**: 290

### Spatial Coordinate Naming

Two naming conventions are used:
- **Short form**: `lat`, `lon` (39.6% of files)
- **Long form**: `latitude`, `longitude` (59.8% of files)

## Known Issues

### Corrupted Files

At least 1 file is corrupted and cannot be read:
- `/home/renatob/data/TRENDYv13/LPX/S3/LPX-Bern_S3_snowdepth.nc`
  - Error: "NetCDF: HDF error (NetCDF error code: -101)"

### Time Unit Parsing Issues

Files with AD format dates generate warnings:
```
ArgumentError: invalid base 10 digit 'A' in "AD"
@ CommonDataModel ~/.julia/packages/CommonDataModel/pO4st/src/cfvariable.jl:141
```

Affected files: All VISIT model S3 simulation files (~33 files)

### Non-Standard Units

50% of time-related attributes use non-standard units that don't follow CF conventions:
- Physical units (kg m-2 s-1, K, W m-2) instead of time units
- Missing units attribute
- Custom formats

## Implications for Conversion

### Required Handling

1. **Time Unit Normalization**
   - Must handle days, months, years, hours formats
   - Must parse various reference date formats
   - Must handle AD format gracefully
   - Must deal with missing/malformed time units

2. **Coordinate Name Standardization**
   - Support both lat/latitude and lon/longitude
   - Convert to ILAMB standard naming

3. **Error Handling**
   - Skip corrupted files
   - Validate NetCDF structure before processing
   - Provide informative error messages

4. **Metadata Validation**
   - Check for required dimensions (time, lat, lon)
   - Verify variable data types
   - Validate attribute completeness

### ILAMB Target Variables

Priority variables for conversion (based on ILAMB requirements):
- Carbon fluxes: `gpp`, `nbp`, `npp`, `ra`, `rh`
- Carbon stocks: `cSoil`, `cVeg`, `cLitter`, `cProduct`
- Water fluxes: `mrro`, `mrros`, `mrso`, `evapotrans`
- Fire: `burntArea`, `fFire`
- Vegetation: `lai`

## Recommendations

1. **Implement robust time parsing** with fallbacks for non-standard formats
2. **Pre-validate files** before attempting conversion
3. **Log skipped files** with reasons (corrupted, missing dimensions, etc.)
4. **Track conversion statistics** by variable and model
5. **Document known issues** in output logs
6. **Consider batch processing** with parallel execution for large datasets

## Analysis Tools

The analysis was performed using:
- Script: `scripts/analyze_trendy_files_v2.jl`
- Output: `trendy_analysis.json` (2.9 MB)
- Packages: NCDatasets.jl, JSON.jl, Statistics.jl, Dates.jl
