"""Common runtime-provider contracts and deterministic session coordination."""

abstract type AbstractShellProvider end

const PROVIDER_STATES = Set([:starting, :ready, :degraded, :unavailable, :stopped])

struct ProviderHealth
    name::String
    state::Symbol
    message::String
    generation::UInt64
end

function ProviderHealth(name::AbstractString, state::Symbol; message="", generation=0)
    state in PROVIDER_STATES || throw(ArgumentError("invalid provider state: $state"))
    ProviderHealth(String(name), state, String(message), UInt64(generation))
end

struct ProviderEvent
    provider::String
    kind::Symbol
    payload::Dict{String,Any}
    occurred_at::DateTime
end

function ProviderEvent(provider::AbstractString, kind::Symbol;
                       payload=Dict{String,Any}(), occurred_at=now(UTC))
    ProviderEvent(String(provider), kind,
        Dict{String,Any}(String(k) => v for (k, v) in payload), occurred_at)
end

provider_name(provider::AbstractShellProvider) = string(nameof(typeof(provider)))
provider_capabilities(::AbstractShellProvider) = String[]
provider_health(provider::AbstractShellProvider) =
    ProviderHealth(provider_name(provider), :unavailable; message="provider has no health implementation")
provider_snapshot(provider::AbstractShellProvider) = Dict{String,Any}(
    "name" => provider_name(provider), "capabilities" => provider_capabilities(provider))
drain_provider_events!(::AbstractShellProvider) = ProviderEvent[]
"Subscribe to provider events. Providers that do not support callbacks return `nothing`."
subscribe_provider!(::AbstractShellProvider, ::Function) = nothing
unsubscribe_provider!(::AbstractShellProvider, token) = false

function invoke_provider!(provider::AbstractShellProvider, action::AbstractString,
                          parameters::AbstractDict=Dict{String,Any}())
    throw(JuliaShellError(:provider_action_unsupported, "provider does not support the requested action";
        details=Dict("provider" => provider_name(provider), "action" => String(action)),
        remediation="inspect provider capabilities before invoking an action"))
end

"Deterministic provider used for coordinator, projection, and failure tests."
mutable struct FakeShellProvider <: AbstractShellProvider
    name::String
    capabilities::Vector{String}
    health::ProviderHealth
    state::Dict{String,Any}
    events::Vector{ProviderEvent}
    actions::Dict{String,Function}
    subscribers::Dict{UInt64,Function}
    next_subscription::UInt64
end

function FakeShellProvider(name::AbstractString; capabilities=String[], state=Dict{String,Any}(),
                           health=:ready, message="")
    selected = String(name)
    FakeShellProvider(selected, sort!(unique!(String[String(value) for value in capabilities])),
        ProviderHealth(selected, health; message),
        Dict{String,Any}(String(k) => v for (k, v) in state), ProviderEvent[],
        Dict{String,Function}(), Dict{UInt64,Function}(), UInt64(0))
end

provider_name(provider::FakeShellProvider) = provider.name
provider_capabilities(provider::FakeShellProvider) = copy(provider.capabilities)
provider_health(provider::FakeShellProvider) = provider.health
provider_snapshot(provider::FakeShellProvider) = copy(provider.state)

function drain_provider_events!(provider::FakeShellProvider)
    events = copy(provider.events)
    empty!(provider.events)
    events
end

function push_provider_event!(provider::FakeShellProvider, kind::Symbol;
                              payload=Dict{String,Any}())
    event = ProviderEvent(provider.name, kind; payload)
    push!(provider.events, event)
    for callback in values(provider.subscribers)
        try
            callback(event)
        catch
            # A subscriber must not be able to break provider state delivery.
        end
    end
    event
end

function subscribe_provider!(provider::FakeShellProvider, callback::Function)
    provider.next_subscription += 1
    provider.subscribers[provider.next_subscription] = callback
    provider.next_subscription
end

subscribe_provider!(callback::Function, provider::AbstractShellProvider) = subscribe_provider!(provider, callback)

function unsubscribe_provider!(provider::FakeShellProvider, token)
    token isa Integer || return false
    pop!(provider.subscribers, UInt64(token), nothing) !== nothing
end

function register_action!(handler::Function, provider::FakeShellProvider, action::AbstractString)
    provider.actions[String(action)] = handler
    provider
end

function invoke_provider!(provider::FakeShellProvider, action::AbstractString,
                          parameters::AbstractDict=Dict{String,Any}())
    handler = get(provider.actions, String(action), nothing)
    handler === nothing && throw(JuliaShellError(:provider_action_unsupported,
        "provider does not support the requested action";
        details=Dict("provider" => provider.name, "action" => String(action)),
        remediation="inspect provider capabilities before invoking an action"))
    handler(Dict{String,Any}(String(k) => v for (k, v) in parameters))
end

mutable struct SessionCoordinator
    providers::Dict{String,AbstractShellProvider}
    events::Vector{ProviderEvent}
    generation::UInt64
    subscribers::Dict{UInt64,Function}
    next_subscription::UInt64
end

SessionCoordinator() = SessionCoordinator(Dict{String,AbstractShellProvider}(), ProviderEvent[], 0,
                                           Dict{UInt64,Function}(), UInt64(0))

function _queue_runtime_event!(coordinator::SessionCoordinator, event::ProviderEvent)
    push!(coordinator.events, event)
    for callback in values(coordinator.subscribers)
        try
            callback(event)
        catch
            # Runtime observers are isolated from provider coordination.
        end
    end
    event
end

function subscribe_runtime!(coordinator::SessionCoordinator, callback::Function)
    coordinator.next_subscription += 1
    coordinator.subscribers[coordinator.next_subscription] = callback
    coordinator.next_subscription
end

subscribe_runtime!(callback::Function, coordinator::SessionCoordinator) = subscribe_runtime!(coordinator, callback)

function unsubscribe_runtime!(coordinator::SessionCoordinator, token)
    token isa Integer || return false
    pop!(coordinator.subscribers, UInt64(token), nothing) !== nothing
end

function register_provider!(coordinator::SessionCoordinator, provider::AbstractShellProvider;
                            replace=false)
    name = provider_name(provider)
    haskey(coordinator.providers, name) && !replace &&
        throw(JuliaShellError(:provider_exists, "a provider with this name is already registered";
            details=Dict("provider" => name), remediation="use replace=true for an intentional replacement"))
    coordinator.providers[name] = provider
    coordinator.generation += 1
    _queue_runtime_event!(coordinator, ProviderEvent(name, :provider_registered;
        payload=Dict("generation" => coordinator.generation)))
    provider
end

function unregister_provider!(coordinator::SessionCoordinator, name::AbstractString)
    provider = pop!(coordinator.providers, String(name), nothing)
    provider === nothing && return false
    coordinator.generation += 1
    _queue_runtime_event!(coordinator, ProviderEvent(name, :provider_unregistered;
        payload=Dict("generation" => coordinator.generation)))
    true
end

function poll_providers!(coordinator::SessionCoordinator)
    for name in sort!(collect(keys(coordinator.providers)))
        for event in drain_provider_events!(coordinator.providers[name])
            _queue_runtime_event!(coordinator, event)
        end
    end
    length(coordinator.events)
end

function drain_runtime_events!(coordinator::SessionCoordinator)
    poll_providers!(coordinator)
    events = copy(coordinator.events)
    empty!(coordinator.events)
    events
end

function invoke_provider!(coordinator::SessionCoordinator, provider_name::AbstractString,
                          action::AbstractString, parameters::AbstractDict=Dict{String,Any}())
    provider = get(coordinator.providers, String(provider_name), nothing)
    provider === nothing && throw(JuliaShellError(:provider_missing, "runtime provider is not registered";
        details=Dict("provider" => String(provider_name)), remediation="inspect the runtime capability snapshot"))
    result = invoke_provider!(provider, action, parameters)
    _queue_runtime_event!(coordinator, ProviderEvent(provider_name, :action_completed;
        payload=Dict("action" => String(action))))
    result
end

function runtime_snapshot(coordinator::SessionCoordinator)
    providers = Dict{String,Any}[]
    aggregate = :ready
    for name in sort!(collect(keys(coordinator.providers)))
        provider = coordinator.providers[name]
        health = provider_health(provider)
        health.state == :unavailable && (aggregate = :unavailable)
        health.state == :degraded && aggregate == :ready && (aggregate = :degraded)
        push!(providers, Dict{String,Any}(
            "name" => name,
            "health" => String(health.state),
            "message" => health.message,
            "generation" => health.generation,
            "capabilities" => provider_capabilities(provider),
            "state" => provider_snapshot(provider),
        ))
    end
    Dict{String,Any}("generation" => coordinator.generation,
        "health" => String(aggregate), "providers" => providers)
end
