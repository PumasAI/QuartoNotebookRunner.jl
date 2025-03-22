JULIA:=julia

default: help

docs-instantiate:
	${JULIA} --project=docs/ -e'import Pkg; Pkg.instantiate()'

changelog: docs-instantiate
	${JULIA} --project=docs/ docs/changelog.jl

test:
	${JULIA} --project -e 'using Pkg; Pkg.test()'

help:
	@echo "The following make commands are available:"
	@echo " - make changelog: update all links in CHANGELOG.md's footer"
	@echo " - make test: run the tests"

.PHONY: default help changelog test
