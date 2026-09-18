"""Build the canonical read-only state consumed by CLI, daemon clients, and QML."""

const PROJECTION_SCHEMA = 1
const STATUSBAR_SCHEMA = 1

function _projection_action(action::PlanAction)
    Dict{String,Any}("id" => action.id, "kind" => String(action.kind),
        "source" => action.source, "target" => action.target, "mode" => action.mode,
        "source_hash" => action.source_hash, "target_hash" => action.target_hash,
        "reason" => action.reason)
end

function _projection_pin(pin::Pin)
    item = Dict{String,Any}(
        "desktop_id" => pin.desktop_id,
        "position" => pin.position,
        "match_app_ids" => copy(pin.match_app_ids),
        "launch" => pin.launch,
        "pinned" => true,
    )
    pin.label === nothing || (item["label"] = pin.label)
    pin.scope === nothing || (item["scope"] = pin.scope)
    item
end

function _projection_output(output::OutputState)
    Dict{String,Any}(
        "id" => output.id,
        "name" => output.name,
        "width" => output.width,
        "height" => output.height,
        "scale" => output.scale,
        "focused" => output.focused,
        "connected" => output.available,
    )
end

function _projection_window(window::ToplevelState)
    Dict{String,Any}(
        "id" => window.ref.id,
        "app_id" => window.app_id,
        "title" => window.title,
        "output" => window.output,
        "workspace" => window.workspace,
        "focused" => window.focused,
        "urgent" => window.urgent,
        "pid" => window.pid,
    )
end

function _projection_workspace(workspace::WorkspaceState)
    Dict{String,Any}(
        "id" => workspace.id,
        "name" => workspace.name,
        "output" => workspace.output,
        "focused" => workspace.focused,
        "urgent" => workspace.urgent,
        "window_count" => workspace.window_count,
    )
end

function _projection_application(entry::DesktopEntry; env=ENV)
    Dict{String,Any}(
        "desktop_id" => entry.desktop_id,
        "label" => entry.name,
        "generic_name" => entry.generic_name,
        "icon" => resolve_icon(entry.icon; env),
        "categories" => copy(entry.categories),
        "terminal" => entry.terminal,
        "exec" => entry.exec !== nothing,
    )
end

function _projection_label(desktop_id::AbstractString)
    value = replace(replace(String(desktop_id), r"\.desktop$" => ""), r"[-_.]+" => " ")
    isempty(value) ? "Unknown application" : titlecase(value)
end

function _selected_outputs(dock::Dock, outputs::Vector{OutputState})
    available = [output for output in outputs if output.available]
    isempty(available) && return String[]
    selected = if dock.output == "all"
        available
    elseif dock.output == "focused"
        focused = findfirst(output -> output.focused, available)
        focused === nothing ? available[1:1] : available[focused:focused]
    else
        focused = findfirst(output -> output.focused, available)
        focused === nothing ? available[1:1] : available[focused:focused]
    end
    String[output.name for output in selected]
end

function _window_identity(window::ToplevelState, entries::ApplicationIndex)
    resolve_application(window.app_id;
        class_name=something(window.class_name, ""),
        exec_basename=something(window.exec_basename, ""), entries=entries)
end

function _identity_desktop_id(identity, fallback::AbstractString)
    value = get(identity, "desktop_id", nothing)
    value === nothing ? String(fallback) : String(value)
end

function _matches_pin(window::ToplevelState, pin::Pin, identity)
    window.app_id in pin.match_app_ids && return true
    normalized_window = normalize_app_id(window.app_id)
    any(normalize_app_id(candidate) == normalized_window for candidate in pin.match_app_ids) && return true
    resolved = get(identity, "desktop_id", nothing)
    resolved !== nothing && String(resolved) == pin.desktop_id
end

function _item_for_windows(desktop_id::AbstractString, windows::Vector{ToplevelState};
                           entry=nothing, pinned=false, pin=nothing, missing=false,
                           resolution=Dict{String,Any}(), env=ENV)
    sorted_windows = sort(copy(windows); by=window -> (window.output, window.workspace, window.ref.id))
    label = if pin !== nothing && pin.label !== nothing
        pin.label
    elseif entry !== nothing
        entry.name
    else
        _projection_label(desktop_id)
    end
    icon = entry === nothing ? nothing : resolve_icon(entry.icon; env)
    item = Dict{String,Any}(
        "id" => (pinned ? "pin:" * String(desktop_id) : "app:" * String(desktop_id)),
        "desktop_id" => String(desktop_id),
        "label" => String(label),
        "icon" => icon,
        "pinned" => pinned,
        "missing" => Bool(missing),
        "running" => !isempty(sorted_windows),
        "focused" => any(window -> window.focused, sorted_windows),
        "urgent" => any(window -> window.urgent, sorted_windows),
        "instance_count" => length(sorted_windows),
        "instances" => [_projection_window(window) for window in sorted_windows],
        "resolution" => resolution,
    )
    pin === nothing || begin
        item["position"] = pin.position
        item["launch"] = pin.launch
        pin.scope === nothing || (item["scope"] = pin.scope)
    end
    isempty(sorted_windows) || begin
        item["output"] = first(sorted_windows).output
        item["workspace"] = first(sorted_windows).workspace
    end
    item
end

function _projection_status(profile::Profile, current_plan::Plan, compositor, state)
    issues = String[]
    isempty(current_plan.conflicts) || push!(issues, "profile has conflicting managed targets")
    isempty(current_plan.unsafe) || push!(issues, "profile contains unsafe paths")
    isempty(current_plan.missing) || push!(issues, "profile has missing sources")
    compositor !== nothing && !is_connected(compositor) && push!(issues, "compositor is disconnected")
    health = if !isempty(current_plan.conflicts) || !isempty(current_plan.unsafe) || !isempty(current_plan.missing)
        "degraded"
    elseif compositor === nothing || !is_connected(compositor)
        "disconnected"
    else
        "ready"
    end
    Dict{String,Any}(
        "health" => health,
        "degraded" => issues,
        "service" => "online",
        "compositor" => compositor === nothing ? "unknown" : compositor_name(compositor),
        "last_transaction" => get(state, "last_transaction", nothing),
    )
end

"Build the stable Julia-owned summary consumed by the dedicated QML statusbar."
function _statusbar_projection(profile::Profile, current_plan::Plan, compositor,
                               status, items, outputs, workspaces)
    Dict{String,Any}(
        "schema" => STATUSBAR_SCHEMA,
        "health" => status["health"],
        "degraded" => copy(status["degraded"]),
        "profile" => profile.name,
        "revision" => current_plan.revision,
        "compositor" => status["compositor"],
        "outputs" => length(outputs),
        "workspaces" => length(workspaces),
        "pinned" => count(item -> Bool(get(item, "pinned", false)), items),
        "running" => count(item -> Bool(get(item, "running", false)), items),
        "focused" => count(item -> Bool(get(item, "focused", false)), items),
        "urgent" => count(item -> Bool(get(item, "urgent", false)), items),
    )
end

"Return one stable dock/application projection from a validated profile."
function state_projection(profile::Profile; repo=".", env=ENV, revision=nothing,
                          compositor=nothing, entries=nothing)
    root = abspath(String(repo))
    current_plan = plan(profile; repo=root, env=env, revision=revision)
    index = entries === nothing ? discover_applications(; env) : entries
    compositor === nothing || refresh_compositor!(compositor)
    outputs = compositor === nothing ? OutputState[] : compositor_outputs(compositor)
    windows = compositor === nothing ? ToplevelState[] : compositor_toplevels(compositor)
    workspaces = compositor === nothing ? WorkspaceState[] : compositor_workspaces(compositor)
    selected_output_names = _selected_outputs(profile.dock, outputs)
    selected = isempty(selected_output_names) ? windows :
        [window for window in windows if isempty(window.output) || window.output in selected_output_names]

    identities = Dict{String,Dict{String,Any}}()
    for window in selected
        identities[window.ref.id] = _window_identity(window, index)
    end

    items = Dict{String,Any}[]
    pinned_ids = Set{String}()
    for pin in ordered_pins(profile.dock)
        push!(pinned_ids, pin.desktop_id)
        entry = get(index, pin.desktop_id, nothing)
        resolution = resolve_application(pin.desktop_id; entries=index)
        matching = [window for window in selected if _matches_pin(window, pin, identities[window.ref.id]) &&
                    (pin.scope === nothing || isempty(window.output) || window.output == pin.scope)]
        missing = entry === nothing && resolution["status"] == "missing"
        push!(items, _item_for_windows(pin.desktop_id, matching; entry, pinned=true, pin,
                                       missing=missing, resolution=resolution, env))
    end

    grouped = Dict{String,Vector{ToplevelState}}()
    resolutions = Dict{String,Dict{String,Any}}()
    for window in selected
        identity = identities[window.ref.id]
        desktop_id = _identity_desktop_id(identity, window.app_id)
        desktop_id in pinned_ids && continue
        push!(get!(grouped, desktop_id, ToplevelState[]), window)
        resolutions[desktop_id] = identity
    end
    for desktop_id in sort(collect(keys(grouped)))
        entry = get(index, desktop_id, nothing)
        push!(items, _item_for_windows(desktop_id, grouped[desktop_id]; entry,
                                       pinned=false, missing=false, resolution=resolutions[desktop_id], env))
    end

    dock = Dict{String,Any}(
        "edge" => profile.dock.edge,
        "output" => profile.dock.output,
        "autohide" => profile.dock.autohide,
        "exclusive_zone" => profile.dock.autohide == "never" ? 72 : 0,
        "selected_outputs" => selected_output_names,
    )
    application_values = [_projection_application(index[id]; env) for id in sort(collect(keys(index)))]
    workspace_values = String[workspace.name for workspace in workspaces]
    status = _projection_status(profile, current_plan, compositor, _runtime_state(; repo=root, env))
    statusbar = _statusbar_projection(profile, current_plan, compositor, status,
                                      items, outputs, workspaces)
    result = Dict{String,Any}(
        "schema" => PROJECTION_SCHEMA,
        "revision" => current_plan.revision,
        "profile" => profile.name,
        "dock" => dock,
        "items" => items,
        "applications" => application_values,
        "windows" => [_projection_window(window) for window in selected],
        "outputs" => [_projection_output(output) for output in outputs],
        "workspaces" => workspace_values,
        "workspace_states" => [_projection_workspace(workspace) for workspace in workspaces],
        "plan" => Dict{String,Any}(
            "id" => current_plan.id,
            "hash" => current_plan.hash,
            "actions" => [_projection_action(action) for action in current_plan.actions],
            "conflicts" => current_plan.conflicts,
            "unsafe" => current_plan.unsafe,
            "missing" => current_plan.missing,
        ),
        "generated_at" => string(now(UTC)),
        "statusbar" => statusbar,
    )
    merge!(result, status)
    result
end

"Load the active profile and build the canonical state projection."
function state_projection(repo::AbstractString="."; profile="personal", env=ENV,
                          compositor=nothing, entries=nothing)
    path = repository_profile_path(repo, profile)
    if !isfile(path)
        return Dict{String,Any}(
            "schema" => PROJECTION_SCHEMA, "revision" => _revision(; repo, env),
            "profile" => String(profile), "health" => "uninitialized", "service" => "online",
            "compositor" => compositor === nothing ? "unknown" : compositor_name(compositor),
            "degraded" => ["profile does not exist"], "dock" => Dict{String,Any}(),
            "items" => Any[], "applications" => Any[], "windows" => Any[], "outputs" => Any[],
            "workspaces" => Any[], "workspace_states" => Any[], "plan" => nothing,
        )
    end
    loaded = try
        load_profile(path)
    catch err
        return Dict{String,Any}(
            "schema" => PROJECTION_SCHEMA, "revision" => _revision(; repo, env),
            "profile" => String(profile), "health" => "invalid", "service" => "online",
            "compositor" => compositor === nothing ? "unknown" : compositor_name(compositor),
            "degraded" => [sprint(showerror, err)], "dock" => Dict{String,Any}(),
            "items" => Any[], "applications" => Any[], "windows" => Any[], "outputs" => Any[],
            "workspaces" => Any[], "workspace_states" => Any[], "plan" => nothing,
        )
    end
    state_projection(loaded; repo, env, revision=_revision(; repo, env), compositor, entries)
end

const projection = state_projection
