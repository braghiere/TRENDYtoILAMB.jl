# Parallel Conversion Strategy for TRENDY to ILAMB

## Challenge: NetCDF/HDF5 Thread-Safety

**Problem**: The NetCDF-C and HDF5 libraries are **not thread-safe**. When multiple Julia threads try to write NetCDF files simultaneously, we get segmentation faults.

**Evidence**: Test with 8 threads crashed with:
```
[1514272] signal (11.128): Segmentation fault
H5FL_fac_free at libhdf5.so
malloc(): unaligned tcache chunk detected
```

## Solutions (Ranked by Ease & Effectiveness)

### ✅ **Option 1: Distributed Processing (RECOMMENDED)**
Use Julia's `Distributed` package with multiple worker processes instead of threads.

**Advantages**:
- Each worker process has its own NetCDF/HDF5 library instance
- True isolation - no memory conflicts
- Linear scalability
- Can use all 96 cores

**How it works**:
```julia
using Distributed
addprocs(48)  # Add 48 worker processes

@everywhere using TRENDYtoILAMB

pmap(files) do file
    convert_file(file)  # Each worker has own NetCDF library
end
```

**Expected speedup**: 30-50x (limited by I/O bandwidth, not CPU)

---

### ✅ **Option 2: Process-Level Parallelism**
Manually split work across multiple Julia processes

**Advantages**:
- Simple bash script coordination
- No Julia distributed programming needed
- Easy to monitor individual processes

**How it works**:
```bash
# Split files into N chunks
julia -p chunk1.jl &
julia -p chunk2.jl &
julia -p chunk3.jl &
...
wait
```

**Expected speedup**: 10-30x

---

### ⚠️ **Option 3: Thread-Safe I/O with Locks**
Serialize NetCDF writes while parallelizing reading

**Advantages**:
- Uses existing threading code
- Simple to implement

**Disadvantages**:
- Limited speedup (writes are serialized)
- Still some parallelism from reading/processing

**How it works**:
```julia
global_nc_lock = ReentrantLock()

Threads.@threads for file in files
    data = read_and_process(file)  # Parallel
    
    lock(global_nc_lock) do
        write_netcdf(data)  # Serialized
    end
end
```

**Expected speedup**: 2-5x (only reading/processing is parallel)

---

### ❌ **Option 4: GPU Acceleration**
Not applicable - NetCDF I/O can't use GPU

---

## Recommended Implementation

**Use Distributed Processing (Option 1)** with these settings:

```julia
using Distributed

# Add workers (one per ~2 cores for I/O bound tasks)
n_workers = min(48, length(files) ÷ 10)  # Don't spawn more workers than needed
addprocs(n_workers)

@everywhere using TRENDYtoILAMB
@everywhere include("conversion_functions.jl")

# Distribute work
results = pmap(all_files) do file_info
    convert_single_file(file_info)
end
```

**Why 48 workers, not 96?**
- I/O bound task (reading/writing NetCDF files)
- Diminishing returns beyond ~50 workers
- Each worker needs ~2-5 GB RAM (you have 561 GB available)
- File system may have concurrent access limits

**Expected performance**:
- Current: ~6 files/hour (1 core)
- With 48 workers: ~150-250 files/hour
- Total time: **3-6 hours** instead of 6 days!

---

## File System Considerations

1. **Concurrent writes**: Your file system should handle 48 simultaneous writes
2. **I/O bandwidth**: May be the ultimate bottleneck
3. **Monitor**: Watch `iostat` to see if we're I/O saturated

---

## Next Steps

1. Implement distributed version
2. Test with small subset (10 workers, 30 files)
3. Monitor system resources
4. Scale up to full 48 workers
5. Compare actual speedup vs sequential

