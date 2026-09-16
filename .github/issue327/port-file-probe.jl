# Time what OMJulia v0.3.2 gives 2 s to happen: omc starting under
# `--interactive=zmq` and writing the port file that `OMCSession` reads. Spawned
# the way that release spawns it, so a slow start and a start that fails look
# here the way they look there.

using Random

suffix = Random.randstring(10)
omhome = ENV["OPENMODELICAHOME"]
ompath = replace(joinpath(omhome, "bin", "omc.exe"), r"[/\\]+" => "/")
portfile = joinpath(tempdir(), "openmodelica.port.julia.$(suffix)")

process = withenv("OPENMODELICAHOME" => omhome) do
    open(pipeline(`$(ompath) --interactive=zmq -z=julia.$(suffix)`))
end

start = time()
while time() - start < 60 && !isfile(portfile)
    sleep(0.02)
end
elapsed = round(time() - start; digits = 2)

println("port file written: ", isfile(portfile))
println("waited: ", elapsed, "s")
println("omc still running: ", process_running(process))
process_exited(process) && println("omc exit code: ", process.exitcode)

kill(process)
