#=
Focused test: convert only `gpp` for the models with exotic time encodings.
  - CABLE-POP : "months since 1700-1-16"        (months-since path)
  - VISIT-UT  : "years since AD 0-Jan-1st"        (years-since path)
  - CARDAMOM  : capital `Time` attr, units "d"    (month-index special case)
=#

using TRENDYtoILAMB
using NCDatasets

const TRENDY_DIR = "/kiwi-data/Data/model/TRENDYv14/S2"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready_test_v14_awkward"

cases = [
    ("CABLE-POP", "CABLE-POP_S2_gpp.nc"),
    ("VISIT-UT",  "VISIT-UT_S2_gpp.nc"),
    ("CARDAMOM",  "CARDAMOM_S2_gpp.nc"),
]

for (model, file) in cases
    println("\n", "="^60, "\n", model, "\n", "="^60)
    input_file = joinpath(TRENDY_DIR, model, "S2", file)
    output_dir = joinpath(OUTPUT_DIR, model, "S2")
    mkpath(output_dir)
    try
        dataset = TRENDYDataset(input_file, model, "S2", "gpp")
        ds = convert_to_ilamb(dataset, output_dir=output_dir)
        println("  ✓ wrote ", basename(ds.path), " (", round(filesize(ds.path)/1e6, digits=1), " MB)")
        verify_conversion(dataset, ds)
    catch e
        println("  ❌ FAILED: ", typeof(e), ": ", e)
        for (i, fr) in enumerate(stacktrace(catch_backtrace())[1:min(6, end)])
            println("     $i. $fr")
        end
    end
end
println("\nDone. Output: ", OUTPUT_DIR)
