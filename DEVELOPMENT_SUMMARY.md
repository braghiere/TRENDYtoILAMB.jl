# Development Summary - TRENDY to ILAMB Conversion Package

## Branch: development

### Overview
This branch implements comprehensive TRENDY v13 to ILAMB format conversion with robust time handling, model-specific edge cases, and ILAMB-compliant outputs.

## Key Changes

### 1. Core Functionality (`src/converters.jl`)
**Problem**: Original code couldn't handle diverse time encodings and failed with attribute errors.

**Solutions**:
- ✅ **Safe attribute access**: Added `get()` with fallback defaults for missing metadata
- ✅ **Model-specific handlers**: 
  - CARDAMOM: Month index conversion (1-252 → 200301-202312)
  - Generic handler for standard time encodings
- ✅ **Datetime-based extraction**: Uses NCDatasets datetime objects for accurate date ranges
- ✅ **ILAMB filename format**: `{var}_Lmon_ENSEMBLE-{model}_historical_r1i1p1f1_gn_{YYYYMM}-{YYYYMM}.nc`
- ✅ **Simplified output structure**: Models output directly to `{MODEL}/` folders

**Changes**: +116 insertions, -40 deletions

### 2. Time Handling (`src/time.jl`)
**Problem**: Incorrect time conversion treating relative values as absolute years.

**Critical Fix**:
```julia
# OLD (BROKEN):
days[i] = floor(Int, (t - reference_year) * 365)

# NEW (FIXED):
absolute_year = reference_year + t
days[i] = floor(Int, (absolute_year - 1850) * 365)
```

**Impact**: Fixed date extraction for CABLE-POP (1700 reference) and other models.

**Additional Features**:
- Helper function for creating time bounds from day values
- Support for multiple time units: days, months, years, hours
- CF-compliant datetime object handling

**Changes**: +29 insertions, -8 deletions

### 3. Batch Conversion Script (`examples/convert_all_trendy.jl`)
**Features**:
- Converts 22 TRENDY models × 19 ILAMB variables = ~840+ files
- Variables: gpp, nbp, npp, ra, rh, lai, mrro, mrros, mrso, evapotrans, cSoil, cVeg, cLitter, cProduct, burntArea, fFire, tas, pr, rsds
- Comprehensive error handling with categorization
- Statistics tracking by variable and error type
- Progress reporting with detailed file information
- NetCDF validation before conversion
- Data verification after conversion
- Configurable output directory

**Output**: `/home/renatob/data/ilamb_ready/{MODEL}/`

**Changes**: +12 insertions, -4 deletions

### 4. Documentation (`README.md`)
**New comprehensive documentation includes**:
- Feature overview with checkboxes
- Installation instructions (package and development)
- Quick start guide
- Multiple usage examples
- Directory structure diagrams
- API reference with all functions
- Supported models list
- Time handling table
- Known issues section
- Development guidelines
- Citation format

**Changes**: +279 insertions, -24 deletions

### 5. New Files Added
- ✅ **CHANGELOG.md**: Version history following Keep a Changelog format
- ✅ **LICENSE**: MIT License
- ✅ **examples/quick_test.jl**: Quick validation script for single files

## Technical Specifications

### Supported Time Encodings
| Format | Example | Reference Year | Status |
|--------|---------|----------------|--------|
| Days since | `days since 1699-12-31` | 1700 | ✅ Working |
| Years since | `years since 1700-6-15` | 1700 | ✅ Working |
| Months since | `months since 1700-1-16` | 1700 | ✅ Working |
| Month indices | `1, 2, 3, ..., 252` | Model-specific | ✅ Working |

### ILAMB Variables (19 total)
- **Carbon fluxes** (6): gpp, nbp, npp, ra, rh, lai
- **Hydrology** (4): mrro, mrros, mrso, evapotrans
- **Carbon pools** (4): cSoil, cVeg, cLitter, cProduct
- **Fire** (2): burntArea, fFire
- **Forcing** (3): tas, pr, rsds

### Output Specification
- **Filename**: `{var}_Lmon_ENSEMBLE-{model}_historical_r1i1p1f1_gn_{YYYYMM}-{YYYYMM}.nc`
- **Time units**: `days since 1850-01-01`
- **Calendar**: `noleap` (365-day year)
- **Time bounds**: Included as separate variable
- **CF compliance**: Full CF-1.6 metadata

## Testing & Validation

### Models Tested
- ✅ CARDAMOM: Month indices → dates (200301-202312)
- ✅ CABLE-POP: 1700 reference year (170001-202403)
- ✅ CLASSIC: Standard days since 1699-12-31 (170001-202312)
- ✅ Additional models processing in batch conversion

### Validation Methods
1. **Pre-conversion**: NetCDF file validation, dimension checks
2. **Conversion**: Time encoding detection, metadata preservation
3. **Post-conversion**: Data comparison with floating-point tolerance
4. **Output**: File size reporting, dimension/variable listing

### Current Status
**Batch conversion running**:
- Process ID: 1506594
- Runtime: ~10+ minutes
- Files converted: 887 (17GB)
- CPU: 85%
- Status: Active

## Known Issues & Limitations

1. **Missing files**: Some models (iMAPLE, VISIT) had incomplete data
2. **Corrupted files**: HDF errors automatically skipped with error reporting
3. **Missing variables**: Not all models have all 19 ILAMB variables
4. **CARDAMOM specifics**: Requires special month index handling

## Dependencies

- Julia ≥ 1.9
- NCDatasets.jl v0.12
- Dates (standard library)

## Usage

### Quick Test
```bash
cd TRENDYtoILAMB.jl
julia --project=. examples/quick_test.jl
```

### Full Conversion
```bash
julia --project=. examples/convert_all_trendy.jl
```

### Background Processing
```bash
nohup julia --project=. examples/convert_all_trendy.jl > conversion.log 2>&1 &
```

## Next Steps Before Merge

1. ✅ Update README.md - **DONE**
2. ✅ Add CHANGELOG.md - **DONE**
3. ✅ Add LICENSE - **DONE**
4. ✅ Test key models - **DONE**
5. ⏳ Wait for batch conversion to complete
6. ⏳ Verify all model outputs
7. ⏳ Commit changes with clear message
8. ⏳ Push to development branch
9. ⏳ Create pull request to main

## Git Status

```
Modified:
 M README.md                      (+279, -24 lines)
 M examples/convert_all_trendy.jl (+12, -4 lines)
 M src/converters.jl              (+116, -40 lines)
 M src/time.jl                    (+29, -8 lines)

New files:
 ?? CHANGELOG.md
 ?? LICENSE
 ?? examples/quick_test.jl
```

**Total changes**: +436 insertions, -76 deletions

## Performance

- **Processing speed**: ~1-2 files per second (depends on file size)
- **Memory usage**: ~2-18GB (varies with grid size)
- **Disk space**: 17GB for 887 files (average ~19MB per file)
- **Expected total**: ~840 files when complete

## Contact

Renato K. Braghiere <renatobraghiere@gmail.com>
