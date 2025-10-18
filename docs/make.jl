using Documenter
using TRENDYtoILAMB

makedocs(
    sitename = "TRENDYtoILAMB.jl",
    format = Documenter.HTML(),
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