#=
Test parallel conversion on a small subset

This script tests the parallel conversion on just a few files to verify:
1. Multi-threading works correctly
2. No race conditions or conflicts
3. Output files are correct
4. Speedup is achieved


⚠️  WARNING: This approach is NOT RECOMMENDED and is archived for reference only.
   NetCDF/HDF5 libraries are not thread-safe, causing segfaults and data corruption.
   Use convert_parallel_manual.jl instead (separate processes, not threads).

Run with:
    julia -t 8 --project=. examples/test_parallel_conversion.jl
=#

using TRENDYtoILAMB
using NCDatasets
using Printf
using Base.Threads

println("="^80)
println("🧪 TESTING PARALLEL CONVERSION")
println("="^80)
println("Julia threads: $(Threads.nthreads())")
println()

if Threads.nthreads() == 1
    println("⚠️  WARNING: Running with only 1 thread!")
    println("   For parallel execution, run with: julia -t auto --project=. ...")
    println()
end

# Test files (select a few small files from different models)
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const TEST_OUTPUT = "/home/renatob/data/ilamb_ready_test_parallel"

# Clean test output directory
if isdir(TEST_OUTPUT)
    println("🗑️  Cleaning previous test output...")
    rm(TEST_OUTPUT, recursive=true)
end
mkpath(TEST_OUTPUT)

# Find a few test files across different models
test_files = []
ilamb_vars = ["gpp", "npp", "nbp", "lai", "cSoil", "cVeg"]

models = filter(x -> isdir(joinpath(TRENDY_DIR, x)) && !startswith(x, "."), readdir(TRENDY_DIR))

for (i, model) in enumerate(models)
    if i > 3  # Test with just 3 models
        break
    end
    
    model_dir = joinpath(TRENDY_DIR, model)
    for sim in ["S3"]  # Just test S3 simulation
        sim_dir = joinpath(model_dir, sim)
        !isdir(sim_dir) && continue
        
        nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
        
        for file in nc_files
            parts = split(basename(file), "_")
            length(parts) < 3 && continue
            
            var = parts[end][1:end-3]
            
            if lowercase(var) in lowercase.(ilamb_vars)
                push!(test_files, (joinpath(sim_dir, file), model, sim, var))
                break  # Just one file per model for quick test
            end
        end
    end
end

println("📊 Test files selected: $(length(test_files))")
for (file, model, sim, var) in test_files
    println("   - $model/$sim: $var ($(round(filesize(file)/1024/1024, digits=1)) MB)")
end
println()

# Test parallel conversion
println("⏱️  Starting parallel conversion test...")
start_time = time()

converted_count = Threads.Atomic{Int}(0)
failed_count = Threads.Atomic{Int}(0)
io_lock = ReentrantLock()

Threads.@threads for (input_file, model, sim, var) in test_files
    thread_id = Threads.threadid()
    output_dir = joinpath(TEST_OUTPUT, model)
    mkpath(output_dir)
    
    try
        Base.lock(io_lock) do
            println("[Thread $thread_id] Converting $model/$var...")
        end
        
        dataset = TRENDYDataset(input_file, model, sim, var)
        ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
        verify_conversion(dataset, ilamb_dataset)
        
        Threads.atomic_add!(converted_count, 1)
        
        Base.lock(io_lock) do
            println("[Thread $thread_id] ✓ $model/$var → $(basename(ilamb_dataset.path))")
        end
        
    catch e
        Threads.atomic_add!(failed_count, 1)
        
        Base.lock(io_lock) do
            println("[Thread $thread_id] ❌ $model/$var: $(typeof(e))")
        end
    end
end

elapsed = time() - start_time

# Summary
println()
println("="^80)
println("🎯 TEST RESULTS")
println("="^80)
println("⏱️  Time: $(round(elapsed, digits=2)) seconds")
println("🧵 Threads: $(Threads.nthreads())")
println()
println("✓ Converted: $(converted_count[])")
println("❌ Failed: $(failed_count[])")

if converted_count[] > 0
    rate_per_hour = (converted_count[] / elapsed) * 3600
    println()
    println("⚡ Rate: $(round(rate_per_hour, digits=1)) files/hour")
    
    # Estimate for full conversion
    total_files = 840  # Approximate total
    est_hours = total_files / rate_per_hour
    println("📈 Estimated time for full conversion: $(round(est_hours, digits=1)) hours")
    
    # Compare to sequential
    sequential_rate = 6.0  # files/hour
    speedup = rate_per_hour / sequential_rate
    println("🚀 Speedup vs sequential: $(round(speedup, digits=1))x")
end

println()
println("📁 Test output: $TEST_OUTPUT")
println("="^80)

# Verify output files
println()
println("🔍 Verifying output files...")
for model in readdir(TEST_OUTPUT)
    model_dir = joinpath(TEST_OUTPUT, model)
    files = filter(x -> endswith(x, ".nc"), readdir(model_dir))
    for file in files
        file_path = joinpath(model_dir, file)
        size_mb = round(filesize(file_path)/1024/1024, digits=2)
        println("   ✓ $model/$file ($size_mb MB)")
        
        # Quick check: can we open it?
        NCDataset(file_path) do ds
            println("      - Time points: $(length(ds["time"]))")
            println("      - Variables: $(join(keys(ds), ", "))")
        end
    end
end

println()
println("✅ Parallel conversion test complete!")
