using Documenter
using Traceur

makedocs(
    sitename = "Traceur",
    format = Documenter.HTML(),
    modules = [Traceur]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
