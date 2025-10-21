#=
Quick test on CARDAMOM only to verify:
1. Output in /home/renatob/data/
2. Files directly in model folder (no S3 subfolder)
3. Proper ILAMB filename format
=#

using TRENDYtoILAMB
using NCDatasets

const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const TEST_OUTPUT = "/home/renatob/data/ilamb_ready_test"

println("="^60)
println("=== Quick CARDAMOM Test ===")
println("="^60)

# Test on one CARDAMOM file
model = "CARDAMOM"
sim = "S3"
var = "gpp"

model_dir = joinpath(TRENDY_DIR, model, sim)
test_file = joinpath(model_dir, "CARDAMOM_S3_gpp.nc")

if isfile(test_file)
    println("\n📄 Testing: $(basename(test_file))")
    
    # Create output directory
    output_dir = joinpath(TEST_OUTPUT, model)
    mkpath(output_dir)
    
    try
        # Convert
        dataset = TRENDYDataset(test_file, model, sim, var)
        ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
        
        # Show results
        println("\n✅ Conversion successful!")
        println("Output file: $(basename(ilamb_dataset.path))")
        println("Full path: $(ilamb_dataset.path)")
        println("File size: $(round(filesize(ilamb_dataset.path)/1024/1024, digits=2)) MB")
        
        # Verify the file
        NCDataset(ilamb_dataset.path) do ds
            println("\nFile contents:")
            println("  Dimensions: $(keys(ds.dim))")
            println("  Variables: $(keys(ds))")
            println("  Time points: $(length(ds["time"]))")
            if haskey(ds, var)
                println("  $var shape: $(size(ds[var]))")
            end
        end
        
    catch e
        println("\n❌ Error: $e")
        rethrow(e)
    end
else
    println("❌ Test file not found: $test_file")
end

println("\n" * "="^60)
