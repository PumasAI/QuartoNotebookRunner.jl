# Loading a package inside a cell can trigger precompilation of one of this
# package's extensions, and from Julia 1.11 that report is written to `stderr`,
# which the cell has captured. The extension is an implementation detail that
# the notebook never asked for, so its report is dropped from the cell's
# output. A report that something failed to precompile stays, since that one
# needs reading.

"""
Names of the extensions that have loaded, in load order. Each extension adds
itself from its `__init__`, which tells a cell which extensions Base could have
written a precompilation report about while that cell ran.
"""
const LOADED_EXTENSIONS = String[]

extension_loaded!(extension::Module) = push!(LOADED_EXTENSIONS, String(nameof(extension)))

const ANSI_ESCAPE = r"\e\[[0-9;]*m"

# `Base.Precompilation` opens a report with a header of its own, prints one
# line per package with a right-aligned duration and a marker, and closes with
# a count.
const REPORT_HEADER = r"^Precompiling (packages\.\.\.|for )"
const REPORT_PACKAGE = r"^ *[\d.]+ ms +[✓?] "
const REPORT_SUMMARY = r"^ *\d+ dependenc(y|ies).*successfully precompiled in "

"""
    strip_worker_precompilation(output, extensions)

Remove `extensions` from the precompilation reports that `output` may contain,
along with a report that names nothing else. With no extension loaded there is
nothing to have reported, and `output` is returned as it came.
"""
function strip_worker_precompilation(output::AbstractString, extensions)
    isempty(extensions) && return output
    any(extension -> occursin(extension, output), extensions) || return output
    _reports_failure(output) && return output

    kept = SubString{String}[]
    report = SubString{String}[]
    for line in split(output, '\n'; keepempty = true)
        plain = replace(line, ANSI_ESCAPE => "")
        if isempty(report) && !contains(plain, REPORT_HEADER)
            push!(kept, line)
            continue
        end
        _names_extension(plain, extensions) && continue
        push!(report, line)
        contains(plain, REPORT_SUMMARY) || continue
        # A report left with no package to its name was about extensions alone,
        # so its header and count go too. Anything else between them is not
        # ours to remove.
        if any(_names_package, report)
            append!(kept, report)
        else
            append!(kept, filter(!_frames_report, report))
        end
        empty!(report)
    end
    append!(kept, report)

    return join(kept, '\n')
end

_names_package(line) = contains(replace(line, ANSI_ESCAPE => ""), REPORT_PACKAGE)

_names_extension(plain, extensions) =
    contains(plain, REPORT_PACKAGE) &&
    any(extension -> occursin(extension, plain), extensions)

function _frames_report(line)
    plain = replace(line, ANSI_ESCAPE => "")
    return contains(plain, REPORT_HEADER) || contains(plain, REPORT_SUMMARY)
end

# A failed build is marked with a cross, counted as errored, and followed by
# whatever the build wrote. None of that is noise.
_reports_failure(output) =
    occursin("✗", output) ||
    occursin("errored", output) ||
    occursin("had output during precompilation", output)
