# Parallel Conversion Exploration Summary

## Goal
Speed up TRENDY to ILAMB conversion from current **6 files/hour** (6 days total) to complete in hours instead of days.

## System Resources
- **CPU**: 96 cores (Intel Xeon Platinum 8168 @ 2.70GHz)
- **RAM**: 754 GB total, 561 GB available
- **GPU**: 2× Tesla V100 (16GB each) - not applicable for NetCDF I/O
- **Current bottleneck**: Single-threaded processing

## Attempted Solutions

### ❌ **Multi-threading (Threads.@threads)** 
**Status**: FAILED - NetCDF/HDF5 not thread-safe

**What we tried**:
- Created `examples/convert_all_trendy_parallel.jl`
- Created `examples/test_parallel_conversion.jl`
- Used `Threads.@threads` with 8 threads

**Result**:
```
[1514272] signal (11.128): Segmentation fault
H5FL_fac_free at libhdf5.so
malloc(): unaligned tcache chunk detected
Aborted (core dumped)
```

**Root cause**: NetCDF-C and HDF5 libraries are not thread-safe. Multiple threads writing NetCDF files simultaneously cause memory corruption and crashes.

**Files created** (for reference only, don't use):
- `examples/convert_all_trendy_parallel.jl` - Multi-threaded version (DOESN'T WORK)
- `examples/test_parallel_conversion.jl` - Test script (DOESN'T WORK)

---

### 🔄 **Distributed Processing (Distributed.pmap)** 
**Status**: IN PROGRESS - Promising approach

**What we're trying**:
- Created `examples/convert_all_trendy_distributed.jl`
- Created `examples/test_distributed_conversion.jl`  
- Uses Julia's `Distributed` package with worker processes
- Each worker has its own NetCDF/HDF5 library instance (isolated)

**Expected benefits**:
- ✅ No thread-safety issues (processes are isolated)
- ✅ Can use 48+ workers
- ✅ Expected speedup: 25-40x
- ✅ Estimated time: 3-6 hours instead of 6 days

**Current status**: Implementation needs refinement for function loading on workers.

---

## Recommended Next Steps

### Option 1: Fix Distributed Implementation (RECOMMENDED)
Continue working on the distributed version since it avoids the NetCDF thread-safety issue entirely.

**TODO**:
1. Fix function loading on workers in `test_distributed_conversion.jl`
2. Test with 4 files across 4 workers
3. Verify no segfaults or memory issues
4. Scale up to 48 workers for full conversion
5. Monitor system resources (RAM, I/O bandwidth)

---

### Option 2: Simple Process-Level Parallelism (EASIEST)
Manually split work across multiple Julia processes without using Distributed package.

**Approach**:
```bash
# Split files into chunks
cd /home/renatob/TRENDYtoILAMB.jl

# Start multiple conversion processes in parallel
julia --project=. -e 'convert_models(["CABLE-POP", "CARDAMOM", "CLASSIC"])' &
julia --project=. -e 'convert_models(["CLM5.0", "DLEM", "IBIS"])' &
julia --project=. -e 'convert_models(["ISAM", "JSBACH", "JULES"])' &
...
wait
```

**Advantages**:
- Simplest to implement
- No complex distributed computing setup
- Easy to monitor individual processes
- Can manually load-balance by model size

**Expected speedup**: 10-20x (limited by manual chunking)

---

### Option 3: Keep Sequential Running
Current process (PID 1512009) is stable and running successfully.

**Status**: 
- 107 files converted in 18 hours
- Memory stable at 0.7% (no leaks)
- Rate: ~6 files/hour
- ETA: ~140 hours (~6 days total)

**Decision point**: Stop and restart with parallel, or let it complete?

---

## Files in This Branch

### Documentation:
- `PARALLEL_STRATEGY.md` - Detailed analysis of parallelization options
- `PARALLEL_EXPLORATION_SUMMARY.md` - This file

### Code (Thread-based - DON'T USE):
- `examples/convert_all_trendy_parallel.jl` - Multi-threaded (FAILS due to NetCDF thread-safety)
- `examples/test_parallel_conversion.jl` - Test for threading (FAILS)

### Code (Process-based - WORK IN PROGRESS):
- `examples/convert_all_trendy_distributed.jl` - Distributed workers (needs testing)
- `examples/test_distributed_conversion.jl` - Test for distributed (needs fixes)

---

## Key Learnings

1. **NetCDF/HDF5 are NOT thread-safe** - Cannot use Julia threading for parallel NetCDF writes
2. **Distributed processing is the solution** - Separate processes avoid the thread-safety issue
3. **96 cores available** - Massive parallelization potential
4. **I/O may be bottleneck** - Even with parallelization, disk I/O may limit speedup to 30-40x instead of 96x

---

## Recommendation

**Don't merge this branch to main yet.** It contains exploratory code that doesn't fully work.

**Next session**: 
1. Fix the distributed version to work properly
2. Test thoroughly with small subset
3. Verify 20-40x speedup
4. Then decide whether to stop sequential run and restart with parallel
5. Create new PR with working parallel version

---

## Current Sequential Run Status

**Don't stop it yet!** Let it continue while we finalize the parallel version.

- Process: 1512009
- Status: Running smoothly
- Files: 107/~840 converted
- Memory: Stable at 0.7%
- Rate: ~6 files/hour
- Output: `/home/renatob/data/ilamb_ready/`

**Monitor with**:
```bash
# Check progress
find /home/renatob/data/ilamb_ready/ -name "*.nc" | wc -l

# Check process
ps -p 1512009 -o pid,%cpu,%mem,etime,cmd

# View log
tail -f /home/renatob/data/conversion_log_20251018_121115.txt
```
