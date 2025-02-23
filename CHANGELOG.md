# QuartoNotebookRunner.jl changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- Fix missing display maths output in Typst. Works around inconsistency in handling of markdown math syntax between Quarto output formats [#262]
- Print out better errors when worker `julia` processes fail to start [#265]

## [v0.13.1] - 2025-02-18

### Fixed

- Adjust notebook startup script to ensure all environments in `LOAD_PATH` are resolved [#257]

## [v0.13.0] - 2025-02-18

### Added

- Support for `{python}` code evaluated using [`PythonCall.jl`](https://github.com/JuliaPy/PythonCall.jl) [#255]

## [v0.12.3] - 2025-02-14

### Fixed

- Fix rendering of `PrettyTables` tables [#253]

## [v0.12.2] - 2025-02-07

### Added

- QuartoNotebookRunner now corrects the png image size metadata it reports to quarto by the dpi stored in the file, if available. This will result in smaller visual image sizes for files with dpi > 96 [#248].

### Fixed

- Fix printing of cell results that contain color [#250]

## [v0.12.1] - 2025-02-04

### Fixed

- When several Juliaup channels are provided the last one is used [#238]

## [v0.12.0] - 2025-01-22

### Added

- Support running different Julia versions in notebook processes [#232]

## [v0.11.7] - 2024-11-25

### Fixed

- Add missing `Random` import [#211]

## [v0.11.6] - 2024-11-07

### Fixed

- Append user `exeflags` to env `exeflags` [#209]

## [v0.11.5] - 2024-10-16

### Fixed

- Deterministic seeded random streams across runs [#194]
- Fix `InitError: ConcurrencyViolationError` [#190]

## [v0.11.4] - 2024-09-30

### Fixed

- Fix global `eval: false` [#174]

## [v0.11.3] - 2024-08-14

### Fixed

- Make parameters `const` [#164]
- Support warning cell option [#166]
- Fix unpopulated notebook options during worker package init [#167]
- Improve cell attribute error messages [#171]

## [v0.11.2] - 2024-06-24

### Fixed

- Pass `:module` to `IOCapture.capture` [#149]
- `print` inline code results instead of `show`ing them [#153]
- Fix Plotly `require.js` config mechanism [#155]

## [v0.11.1] - 2024-06-07

### Fixed

- Fix `revise_first` world age issue [#138]
- Use `invokelatest` in `expand` to allow extension within notebooks [#140]
- LaTeX rendering improvements [#147]
- `InteractiveUtils` should be imported by default [#148]

## [v0.11.0] - 2024-05-28

### Added

- Support REPL modes [#121]
- Make `'--color=yes'` the default [#122]
- Implement `expand` extension interface and `Cell` struct [#135]
- Handle `application/pdf` mimetypes [#136]

## [v0.10.2] - 2024-05-02

### Fixed

- Error handling for `expand`ed cells [#119]

## [v0.10.1] - 2024-04-29

### Fixed

- Use `code` field of for source of expanded cells [#114]

## [v0.10.0] - 2024-04-18

### Added

- `RCall.jl` plot support [#95]
- Add ability to render R code blocks with `RCall` [#100]
- Implement notebook parameters [#105]

### Fixed

- try-catch `pwd` in case it's deleted after starting the server [#96]
- Close socket when receiving invalid json or hmac [#98]

## [v0.9.1] - 2024-04-08

### Fixed

- Improve serialization behaviour [#87]

## [v0.9.0] - 2024-04-02

### Added

- Wrap evaluation errors in `EvaluationError` exception [#81]
- Progress updates for `"run"` command over socket server [#83]

## [v0.8.1] - 2024-03-25

### Fixed

- Use `flatmap` for cell expansion [#74]
- Remove `PNGFiles` dependency [#79]

## [v0.8.0] - 2024-03-21

### Added

- Dynamic cell expansion [#71]
- Use `--project=@.` as default environment [#73]

## [v0.7.1] - 2024-03-15

### Fixed

- Timeout server only if no workers are present [#68]

## [v0.7.0] - 2024-03-14

### Added

- HMAC signing [#64]

## [v0.6.0] - 2024-03-13

### Added

- Add timeout feature for workers [#61]
- Socket server timeout [#62]

### Fixed

- Improve thread-safety [#60]

## [v0.5.0] - 2024-03-08

### Added

- Encapsulate server connection logic [#59]

## [v0.4.2] - 2024-03-06

### Fixed

- Limit rendered output [#58]

## [v0.4.1] - 2024-03-06

### Fixed

- Render inline Plotly plots, not entire HTML pages [#52]
- Return julia error so that quarto can display why execution failed [#53]
- Get `exeflags` and `env` keys with fallback [#54]
- Precompile server machinery [#55]

## [v0.4.0] - 2024-02-29

### Fixed

- Fix undefined ref error on Julia 1.6 [#47]
- Don't create any output for `nothing` [#48]

## [v0.3.3] - 2024-02-29

### Added

- Support `julia.env` frontmatter [#45]

## [v0.3.2] - 2024-02-27

### Added

- Add `isopen` and `isready` commands to server protocol [#43]

## [v0.3.1] - 2024-02-20

### Fixed

- Support `include` in notebooks [#34]

## [v0.3.0] - 2024-02-11

### Added

- Support inline code syntax [#32]

## [v0.2.1] - 2024-02-08

### Fixed

- Add support for suppressing output via `;` [#28]
- Correct YAML handling in cells [#31]

## [v0.2.0] - 2024-02-02

### Added

- Project frontmatter [#18]
- Implement non-standard MIME handling [#23]
- Allow setting error to control reporting of cell errors [#26]

## [v0.1.3] - 2024-01-25

### Fixed

- Fix CairoMakie behavior for figure width and dpi settings [#14]

## [v0.1.2] - 2024-01-17

### Fixed

- Handle trailing markdown content in QMD files correctly [#11]

## [v0.1.1] - 2024-01-15

### Fixed

- Adjust precompile workload to avoid warnings [#9]

## [v0.1.0] - 2024-01-10

- Initial release


<!-- Links generated by Changelog.jl -->

[v0.1.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.1.0
[v0.1.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.1.1
[v0.1.2]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.1.2
[v0.1.3]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.1.3
[v0.2.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.2.0
[v0.2.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.2.1
[v0.3.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.3.0
[v0.3.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.3.1
[v0.3.2]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.3.2
[v0.3.3]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.3.3
[v0.4.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.4.0
[v0.4.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.4.1
[v0.4.2]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.4.2
[v0.5.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.5.0
[v0.6.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.6.0
[v0.7.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.7.0
[v0.7.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.7.1
[v0.8.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.8.0
[v0.8.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.8.1
[v0.9.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.9.0
[v0.9.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.9.1
[v0.10.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.10.0
[v0.10.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.10.1
[v0.10.2]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.10.2
[v0.11.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.0
[v0.11.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.1
[v0.11.2]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.2
[v0.11.3]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.3
[v0.11.4]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.4
[v0.11.5]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.5
[v0.11.6]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.6
[v0.11.7]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.11.7
[v0.12.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.12.0
[v0.12.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.12.1
[v0.12.2]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.12.2
[v0.12.3]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.12.3
[v0.13.0]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.13.0
[v0.13.1]: https://github.com/PumasAI/QuartoNotebookRunner.jl/releases/tag/v0.13.1
[#9]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/9
[#11]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/11
[#14]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/14
[#18]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/18
[#23]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/23
[#26]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/26
[#28]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/28
[#31]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/31
[#32]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/32
[#34]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/34
[#43]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/43
[#45]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/45
[#47]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/47
[#48]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/48
[#52]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/52
[#53]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/53
[#54]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/54
[#55]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/55
[#58]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/58
[#59]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/59
[#60]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/60
[#61]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/61
[#62]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/62
[#64]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/64
[#68]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/68
[#71]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/71
[#73]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/73
[#74]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/74
[#79]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/79
[#81]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/81
[#83]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/83
[#87]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/87
[#95]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/95
[#96]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/96
[#98]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/98
[#100]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/100
[#105]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/105
[#114]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/114
[#119]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/119
[#121]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/121
[#122]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/122
[#135]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/135
[#136]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/136
[#138]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/138
[#140]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/140
[#147]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/147
[#148]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/148
[#149]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/149
[#153]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/153
[#155]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/155
[#164]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/164
[#166]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/166
[#167]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/167
[#171]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/171
[#174]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/174
[#190]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/190
[#194]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/194
[#209]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/209
[#211]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/211
[#232]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/232
[#238]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/238
[#248]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/248
[#250]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/250
[#253]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/253
[#255]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/255
[#257]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/257
[#262]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/262
[#265]: https://github.com/PumasAI/QuartoNotebookRunner.jl/issues/265
