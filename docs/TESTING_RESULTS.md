# Testing Results - TRENDYtoILAMB.jl

Testing performed: October 17, 2025

## Test Configuration

- **Test Script**: `examples/test_convert_single_model.jl`  
- **Model Tested**: CABLE-POP
- **Simulation**: S3
- **Files Found**: 50 NetCDF files
- **ILAMB-relevant Files**: 3 (cLitter, cProduct, cSoil)

## Critical Bug Discovered

### Issue: `create_time_bounds` Method Error

**Error Type**: `MethodError`

**Location**: `src/converters.jl:86`

**Problem**: The `create_time_bounds` function expects `Vector{<:Real}` but receives `DateTimeNoLeap` objects from NCDatasets.jl

**Error Message**:
```
MethodError(TRENDYtoILAMB.create_time_bounds, 
  (DateTimeNoLeap[DateTimeNoLeap(1700-06-15T12:00:00), ...], 1700), 
  0x00000000000082d6)
```

**Affected Files**:
- All CABLE-POP S3 files tested (100% failure rate)
- cLitter.nc
- cProduct.nc  
- cSoil.nc

**Root Cause**:
The `create_time_bounds` function in `src/time.jl` is defined as:
```julia
function create_time_bounds(years::Vector{<:Real}, reference_year::Int=1850)
```

But the converter passes `DateTimeNoLeap` arrays directly without conversion.

## Required Fixes

### 1. Add DateTimeNoLeap Handling

**File**: `src/time.jl`

Add a new method to handle `DateTimeNoLeap`:

```julia
function create_time_bounds(datetimes::Vector{<:CFTime.AbstractCFDateTime}, reference_year::Int)
    # Convert CFTime to years since reference
    years = [dayofyear(dt) / 365.0 + year(dt) - reference_year for dt in datetimes]
    return create_time_bounds(years, reference_year)
end
```

### 2. Alternative: Convert Before Calling

**File**: `src/converters.jl` around line 86

Convert `DateTimeNoLeap` to numeric years before calling `create_time_bounds`:

```julia
# Convert time to years since reference if needed
if eltype(years) <: CFTime.AbstractCFDateTime
    years_numeric = [year(dt) - reference_year + (dayofyear(dt) - 1) / 365.0 for dt in years]
    time_bounds = create_time_bounds(years_numeric, reference_year)
else
    time_bounds = create_time_bounds(years, reference_year)
end
```

## Data Insights from Testing

### Time Representation in CABLE-POP

- **Time Units**: "years since 1700-6-15 12:00:00"
- **Time Points**: 324 values
- **Date Range**: 1700-06-15 to 2023-09-01
- **Calendar**: DateTimeNoLeap (365-day calendar, no leap years)
- **Reference Year**: 1700

### File Structure

All tested files share common structure:
- **Dimensions**: latitude (180), longitude (360), time (324)
- **Spatial Coverage**: Global
- **Variables**: Carbon stocks (kg m-2)

## Next Steps

1. **Fix `create_time_bounds` function** to handle CFTime types
2. **Add type checking** in converters to handle different time representations
3. **Add unit tests** for DateTimeNoLeap conversion
4. **Test with other models** to identify model-specific issues
5. **Document time handling** in API documentation

## Testing Recommendations

### Short-term
1. Fix the `create_time_bounds` bug
2. Re-run test on CABLE-POP
3. Test one file from each model

### Medium-term
1. Create comprehensive test suite with different time formats
2. Add tests for all calendar types (360-day, 365-day, standard)
3. Validate output files against ILAMB requirements

### Long-term
1. Set up continuous integration
2. Add regression tests
3. Create benchmark suite for performance testing

## Success Criteria

Before running full conversion (`convert_all_trendy.jl`):

- [ ] Fix `create_time_bounds` to handle DateTimeNoLeap
- [ ] Successfully convert at least one file from each model
- [ ] Verify output files are ILAMB-compliant
- [ ] Document known issues and workarounds
- [ ] Create error handling for unsupported time formats

## Lessons Learned

1. **Testing pays off**: Found critical bug before running full dataset
2. **Time handling is complex**: Different models use different calendars
3. **Type safety matters**: Need to handle CFTime types explicitly
4. **Incremental testing**: Test single model before full dataset
5. **Error messages are helpful**: Clear error pointed directly to the problem

## Impact Assessment

**Severity**: HIGH  
**Impact**: 100% of conversions fail  
**Priority**: CRITICAL - Must fix before any production use

This bug would have caused the full `convert_all_trendy.jl` script to fail on all files, wasting significant computation time. Early testing saved hours of debugging.
