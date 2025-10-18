using Documenter
using Pkg

# Clean environment setup
Pkg.activate(@__DIR__)
if isfile(joinpath(@__DIR__, "Manifest.toml"))
    rm(joinpath(@__DIR__, "Manifest.toml"))
end
Pkg.develop(PackageSpec(path=joinpath(@__DIR__, "..")))
Pkg.instantiate()

using TRENDYtoILAMB

makedocs(
    sitename = "TRENDYtoILAMB.jl",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://braghiere.github.io/TRENDYtoILAMB.jl"
    ),
    modules = [TRENDYtoILAMB],
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Getting Started" => "manual/getting_started.md",
            "TRENDY Format" => "manual/trendy_format.md",
            "ILAMB Format" => "manual/ilamb_format.md",
        ],
        "API Reference" => "api.md",
    ]
)

deploydocs(
    repo = "github.com/braghiere/TRENDYtoILAMB.jl.git",
)