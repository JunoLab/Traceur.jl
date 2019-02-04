using Documenter
using Traceur

makedocs(
    sitename = "Traceur",
    format = Documenter.HTML(),
    modules = [Traceur]
)

deploydocs(
    repo = "github.com/JunoLab/Traceur.jl.git"
)
