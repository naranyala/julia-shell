using Test

# This file intentionally includes the abstraction directly. It must not
# require JuliaShell, Protocol, Domain, or any live desktop integration.
module StandaloneCompositorAbstractions
include(joinpath(@__DIR__, "..", "src", "CompositorAbstractions.jl"))
end
const StandaloneCompositor = StandaloneCompositorAbstractions.CompositorAbstractions
@testset "standalone compositor abstraction" begin
    compositor = StandaloneCompositor.FakeCompositor(
        outputs=[StandaloneCompositor.OutputState("HDMI-A-1"; focused=true)],
        toplevels=[StandaloneCompositor.ToplevelState("one", "editor"; output="HDMI-A-1", workspace="1", focused=true),
                   StandaloneCompositor.ToplevelState("two", "terminal"; output="HDMI-A-1", workspace="1", urgent=true),
                   StandaloneCompositor.ToplevelState("three", "browser"; output="HDMI-A-1", workspace="2")])

    @test StandaloneCompositor.compositor_name(compositor) == "fake"
    @test StandaloneCompositor.is_connected(compositor)
    workspaces = StandaloneCompositor.compositor_workspaces(compositor)
    @test [workspace.name for workspace in workspaces] == ["1", "2"]
    @test workspaces[1].window_count == 2
    @test workspaces[1].focused
    @test workspaces[1].urgent

    received = StandaloneCompositor.CompositorEvent[]
    token = StandaloneCompositor.subscribe_compositor!(compositor) do event
        push!(received, event)
    end
    @test token == 1
    StandaloneCompositor.focus_toplevel!(compositor, "two")
    @test received[1].kind == :focus_changed
    @test StandaloneCompositor.drain_events!(compositor)[1].kind == :focus_changed
    @test StandaloneCompositor.unsubscribe_compositor!(compositor, token)
    @test !StandaloneCompositor.unsubscribe_compositor!(compositor, token)

    bad_token = StandaloneCompositor.subscribe_compositor!(compositor) do _
        error("observer failure must be isolated")
    end
    StandaloneCompositor.push_event!(compositor, StandaloneCompositor.CompositorEvent(:observer_probe))
    @test StandaloneCompositor.drain_events!(compositor)[1].kind == :observer_probe
    @test StandaloneCompositor.unsubscribe_compositor!(compositor, bad_token)
    @test !StandaloneCompositor.unsubscribe_compositor!(compositor, -1)
    @test !StandaloneCompositor.unsubscribe_compositor!(compositor, true)

    mutating = StandaloneCompositor.subscribe_compositor!(compositor) do event
        event.payload["items"] = ["changed"]
    end
    original = ["original"]
    StandaloneCompositor.push_event!(compositor,
        StandaloneCompositor.CompositorEvent(:isolation; payload=Dict("items" => original)))
    original[1] = "caller-changed"
    isolated = only(StandaloneCompositor.drain_events!(compositor))
    @test isolated.payload["items"] == ["original"]
    @test StandaloneCompositor.unsubscribe_compositor!(compositor, mutating)

    focused_before = [window.ref.id for window in StandaloneCompositor.compositor_toplevels(compositor) if window.focused]
    StandaloneCompositor.switch_workspace!(compositor, "2"; output="HDMI-A-1")
    focused_after = [window.ref.id for window in StandaloneCompositor.compositor_toplevels(compositor) if window.focused]
    @test focused_after == focused_before
    workspace_event = only(StandaloneCompositor.drain_events!(compositor))
    @test workspace_event.payload == Dict("workspace" => "2", "output" => "HDMI-A-1")

    receipt = StandaloneCompositor.launch_application!(compositor, ["example", "--flag"])
    receipt.argv[1] = "mutated"
    launch_event = only(StandaloneCompositor.drain_events!(compositor))
    @test compositor.launches == [["example", "--flag"]]
    @test launch_event.payload["argv"] == ["example", "--flag"]
    @test receipt.id == "1"

    disconnected = StandaloneCompositor.FakeCompositor(connected=false)
    @test !StandaloneCompositor.refresh_compositor!(disconnected)
    @test_throws StandaloneCompositor.CompositorError StandaloneCompositor.focus_toplevel!(disconnected, "missing")
    @test_throws StandaloneCompositor.CompositorError StandaloneCompositor.launch_application!(disconnected, ["example"])
    @test isempty(disconnected.launches)
    @test isempty(StandaloneCompositor.drain_events!(disconnected))
    @test_throws StandaloneCompositor.CompositorError StandaloneCompositor.focus_toplevel!(compositor, "missing")
    @test_throws StandaloneCompositor.CompositorError StandaloneCompositor.launch_application!(compositor, String[])
end
