using Test
using TRENDYtoILAMB
using NCDatasets

@testset "TRENDYtoILAMB.jl" begin
    @testset "Time conversion" begin
        years = [2000, 2001, 2002]
        days = convert_time_to_days(years, 1850)
        @test length(days) == length(years)
        @test days[1] == (2000 - 1850) * 365
        
        bounds = create_time_bounds(years, 1850)
        @test size(bounds) == (3, 2)
        @test bounds[1,2] - bounds[1,1] == 364  # One year minus one day
    end
    
    @testset "Unit standardization" begin
        @test standardize_units("gC/m^2") == "kg m-2"
        @test standardize_units("unknown_unit") == "unknown_unit"
    end
    
    @testset "Variable metadata" begin
        metadata = get_variable_metadata("cVeg")
        @test metadata.name == "cVeg"
        @test metadata.units == "kg m-2"
    end
end