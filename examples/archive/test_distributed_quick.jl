#=
Quick test of distributed conversion with 3 workers and 6 files
=#

using Distributed

println("="^80)
println("🧪 QUICK DISTRIBUTED TEST")
println("="^80)

# Add just 3 workers for testing
addprocs(3; exeflags="--project=.")
println("Workers: $(nworkers())")

@everywhere using TRENDYtoILAMB
@everywhere using NCDatasets

@everywhere begin
    function convert_file_task(input_file, model, sim, var, output_dir)
        worker_id = myid()
        try
            NCDataset(input_file) do ds
                if !("time" in keys(ds.dim))
                    return (false, model, sim, var, "No time dimension")
                end
            end
            
            dataset = TRENDYDataset(input_file, model, sim, var)
            ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
            verify_conversion(dataset, ilamb_dataset)
            
            size_mb = round(filesize(ilamb_dataset.path) / 1024 / 1024, digits=2)
            return (true, model, sim, var, "✓ $(basename(ilamb_dataset.path)) ($size_mb MB) [W$worker_id]")
        catch e
            return (false, model, sim, var, "Error: $(typeof(e))")
        end
    end
end

# Test files
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const TEST_OUTPUT = "/home/renatob/data/ilamb_ready_test_dist_quick"

if isdir(TEST_OUTPUT)
    rm(TEST_OUTPUT, recursive=true)
end
mkpath(TEST_OUTPUT)

# Get 6 test files
test_tasks = []
vars_to_test = ["cSoil", "gpp"]
models = filter(x -> isdir(joinpath(TRENDY_DIR, x)) && !startswith(x, "."), readdir(TRENDY_DIR))

for model in models[1:3]  # First 3 models
    model_dir = joinpath(TRENDY_DIR, model)
    sim_dir = joinpath(model_dir, "S3")
    !isdir(sim_dir) && continue
    
    output_dir = joinpath(TEST_OUTPUT, model)
    mkpath(output_dir)
    
    for file in readdir(sim_dir)
        !endswith(file, ".nc") && continue
        parts = split(basename(file), "_")
        length(parts) < 3 && continue
        var = parts[end][1:end-3]
        
        if lowercase(var) in lowercase.(vars_to_test)
            push!(test_tasks, (joinpath(sim_dir, file), model, "S3", var, output_dir))
        end
        
        length(test_tasks) >= 6 && break
    end
    length(test_tasks) >= 6 && break
end

println("Testing with $(length(test_tasks)) files:")
for (file, model, sim, var, _) in test_tasks
    println("  - $model/$sim/$var")
end
println()

println("⏱️  Starting conversion...")
start_time = time()

results = pmap(test_tasks) do task
    input_file, model, sim, var, output_dir = task
    convert_file_task(input_file, model, sim, var, output_dir)
end

elapsed = time() - start_time

println()
println("="^80)
println("Results:")
println("="^80)

let success_count = 0
    for (success, model, sim, var, msg) in results
        println("$model/$sim/$var: $msg")
        success && (success_count += 1)
    end
    
    global final_success_count = success_count
end

println()
println("="^80)
println("✓ Success: $final_success_count/$(length(test_tasks))")
println("⏱️  Time: $(round(elapsed, digits=2)) seconds")

if final_success_count > 0
    rate = (final_success_count / elapsed) * 3600
    println("⚡ Rate: $(round(rate, digits=1)) files/hour")
    println("🚀 Speedup vs sequential (4.2 f/h): $(round(rate/4.2, digits=1))x")
end

println("="^80)

rmprocs(workers())
println("✅ Test complete!")
