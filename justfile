default:
    just -l

changelog:
    julia --project=.ci .ci/changelog.jl

close:
    kill $(ps aux | grep '[j]ulia.*quartonotebookrunner\.jl' | awk '{print $2}')

format:
    julia --project=.ci .ci/format.jl

revise *args:
    julia --startup-file=no --project=revise -e 'import Pkg; Pkg.develop(; path = ".")'
    julia --startup-file=no revise/quarto.jl {{args}}
