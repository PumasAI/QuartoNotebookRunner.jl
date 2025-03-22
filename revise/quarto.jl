isempty(ARGS) && error("No arguments provided")
run(addenv(`$ARGS`, "QUARTO_JULIA_PROJECT" => @__DIR__))
