"""Native systemd lifecycle notifications and a user-unit manager boundary."""

abstract type AbstractServiceManager end

struct SystemdUnitState
    name::String
    load_state::String
    active_state::String
    sub_state::String
    unit_file_state::String
    description::String
end

mutable struct SystemctlManager <: AbstractServiceManager
    executable::String
    environment::Dict{String,String}
end

function SystemctlManager(; executable=nothing, env=ENV)
    binary = executable === nothing ? Sys.which("systemctl") : String(executable)
    binary === nothing && throw(JuliaShellError(:systemd_unavailable, "systemctl is not installed";
        remediation="install systemd or use another service-manager adapter"))
    SystemctlManager(String(binary), Dict{String,String}(String(k) => String(v) for (k, v) in env))
end

const _libsystemd = Ref{Ptr{Cvoid}}(C_NULL)
const _libsystemd_checked = Ref(false)

function _libsystemd_handle()
    _libsystemd_checked[] && return _libsystemd[]
    _libsystemd_checked[] = true
    for candidate in ("libsystemd.so.0", "libsystemd.so")
        handle = Libdl.dlopen_e(candidate)
        handle == C_NULL || return (_libsystemd[] = handle)
    end
    C_NULL
end

systemd_available() = _libsystemd_handle() != C_NULL

"Send one native sd_notify state block. Absence of systemd is a supported no-op."
function systemd_notify(state::AbstractString; unset_environment=false)
    isempty(state) && throw(ArgumentError("systemd notification state cannot be empty"))
    handle = _libsystemd_handle()
    handle == C_NULL && return false
    symbol = Libdl.dlsym_e(handle, :sd_notify)
    symbol == C_NULL && return false
    result = ccall(symbol, Cint, (Cint, Cstring), unset_environment ? 1 : 0, String(state))
    result < 0 && throw(JuliaShellError(:systemd_notify_failed, "systemd rejected a lifecycle notification";
        details=Dict("errno" => -result), remediation="inspect the user service and journal"))
    result > 0
end

_notify_line(value::AbstractString) = replace(String(value), '\n' => ' ')

function notify_ready!(; status="julia-shell daemon is ready")
    systemd_notify("READY=1\nSTATUS=" * _notify_line(status))
end

notify_status!(status::AbstractString) = systemd_notify("STATUS=" * _notify_line(status))
notify_watchdog!() = systemd_notify("WATCHDOG=1")
notify_stopping!(; status="julia-shell daemon is stopping") =
    systemd_notify("STOPPING=1\nSTATUS=" * _notify_line(status))

"Return the recommended half-period for watchdog notifications, or nothing."
function watchdog_interval_seconds(; env=ENV, pid=getpid())
    raw = get(env, "WATCHDOG_USEC", "")
    isempty(raw) && return nothing
    usec = tryparse(UInt64, raw)
    (usec === nothing || usec == 0) && return nothing
    watchdog_pid = tryparse(Int, get(env, "WATCHDOG_PID", string(pid)))
    watchdog_pid == pid || return nothing
    max(Float64(usec) / 2_000_000, 0.1)
end

function _systemctl(manager::SystemctlManager, arguments::Vector{String}; check=true)
    command = setenv(Cmd(vcat([manager.executable, "--user", "--no-pager"], arguments)),
                     manager.environment)
    output = IOBuffer()
    error_output = IOBuffer()
    process = run(pipeline(ignorestatus(command), stdout=output, stderr=error_output))
    if check && !success(process)
        throw(JuliaShellError(:systemd_command_failed, "systemd user-unit operation failed";
            details=Dict("arguments" => arguments, "exit_code" => process.exitcode,
                         "stderr" => strip(String(take!(error_output)))),
            remediation="inspect systemctl --user status and the user journal"))
    end
    String(take!(output)), String(take!(error_output)), process.exitcode
end

function _parse_systemctl_show(name::AbstractString, payload::AbstractString)
    values = Dict{String,String}()
    for line in eachline(IOBuffer(payload))
        isempty(line) && continue
        parts = split(line, '='; limit=2)
        length(parts) == 2 && (values[parts[1]] = parts[2])
    end
    SystemdUnitState(String(name), get(values, "LoadState", "unknown"),
        get(values, "ActiveState", "unknown"), get(values, "SubState", "unknown"),
        get(values, "UnitFileState", "unknown"), get(values, "Description", ""))
end

function _unit_name(name::AbstractString)
    value = String(name)
    occursin(r"^[A-Za-z0-9:_.@-]+\.(service|target|socket|timer|path|mount|scope|slice)$", value) ||
        throw(ArgumentError("invalid systemd unit name: $value"))
    value
end

function unit_state(manager::SystemctlManager, name::AbstractString)
    unit = _unit_name(name)
    output, _, _ = _systemctl(manager, ["show",
        "--property=LoadState,ActiveState,SubState,UnitFileState,Description", "--", unit])
    _parse_systemctl_show(name, output)
end

start_unit!(manager::SystemctlManager, name::AbstractString) =
    (_systemctl(manager, ["start", "--", _unit_name(name)]); unit_state(manager, name))
stop_unit!(manager::SystemctlManager, name::AbstractString) =
    (_systemctl(manager, ["stop", "--", _unit_name(name)]); unit_state(manager, name))
restart_unit!(manager::SystemctlManager, name::AbstractString) =
    (_systemctl(manager, ["restart", "--", _unit_name(name)]); unit_state(manager, name))
enable_unit!(manager::SystemctlManager, name::AbstractString; now=false) =
    (_systemctl(manager, vcat(["enable"], now ? ["--now"] : String[], ["--", _unit_name(name)])); true)
disable_unit!(manager::SystemctlManager, name::AbstractString; now=false) =
    (_systemctl(manager, vcat(["disable"], now ? ["--now"] : String[], ["--", _unit_name(name)])); true)
reload_systemd!(manager::SystemctlManager) = (_systemctl(manager, ["daemon-reload"]); true)
