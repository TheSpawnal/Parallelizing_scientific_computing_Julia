"""
A simple cooperative multitasking scheduler that demonstrates
how to implement a more structured approach to task management
with time slicing, priorities, and debugging.

This example creates a complete cooperative multitasking system with coroutines that yield control voluntarily. 
It includes time slicing, priorities, and various task types (timers, workers, event handlers).
The code demonstrates how to build a structured concurrency system from Julia's lower-level primitives, 
with detailed monitoring and visualization of the scheduler's operation.
Each example includes colorful output for better visualization of the asynchronous operations and detailed explanations of what's happening at each step.
"""

using Printf
using Dates

# Define ANSI color and style codes for pretty printing
const TERM_STYLES = Dict(
    :reset      => "\e[0m",
    :bold       => "\e[1m",
    :dim        => "\e[2m",
    :italic     => "\e[3m",
    :underline  => "\e[4m",
    :black      => "\e[30m",
    :red        => "\e[31m",
    :green      => "\e[32m",
    :yellow     => "\e[33m",
    :blue       => "\e[34m",
    :magenta    => "\e[35m",
    :cyan       => "\e[36m",
    :white      => "\e[37m",
    :bg_black   => "\e[40m",
    :bg_red     => "\e[41m",
    :bg_green   => "\e[42m",
    :bg_yellow  => "\e[43m",
    :bg_blue    => "\e[44m",
    :bg_magenta => "\e[45m",
    :bg_cyan    => "\e[46m",
    :bg_white   => "\e[47m"
)

# Stylized printing function
function styled_print(message; style=:reset, timestamp=true)
    style_code = get(TERM_STYLES, style, TERM_STYLES[:reset])
    ts = timestamp ? "[$(Dates.format(now(), "HH:MM:SS.sss"))] " : ""
    println(style_code, ts, message, TERM_STYLES[:reset])
end

# Coroutine state
@enum CoroutineState READY RUNNING SUSPENDED COMPLETED FAILED

# Coroutine priority
@enum CoroutinePriority LOW=1 NORMAL=2 HIGH=3 CRITICAL=4

# Coroutine structure
mutable struct Coroutine
    id::String
    name::String
    priority::CoroutinePriority
    state::CoroutineState
    iterator::Union{Channel{Nothing}, Nothing}
    created_at::DateTime
    last_run::Union{DateTime, Nothing}
    run_count::Int
    total_runtime::Float64  # in seconds
    last_error::Union{Exception, Nothing}
    
    # Constructor
    function Coroutine(id, name, func, priority=NORMAL)
        # Create a channel to communicate with the coroutine
        channel = Channel{Nothing}(1)
        
        # Create the task that will run the coroutine function
        @async begin
            try
                func(channel)
            catch e
                # If the coroutine throws an exception, store it
                coroutine = scheduler.coroutines[id]
                coroutine.state = FAILED
                coroutine.last_error = e
                styled_print("❌ Coroutine $(id) ($(name)) failed: $(e)", style=:red)
            end
        end
        
        return new(
            id, 
            name, 
            priority, 
            READY, 
            channel, 
            now(), 
            nothing, 
            0, 
            0.0, 
            nothing
        )
    end
end

# Scheduler structure
mutable struct Scheduler
    coroutines::Dict{String, Coroutine}
    active::Bool
    time_slice::Float64  # seconds per coroutine time slice
    debug::Bool
    current_coroutine::Union{String, Nothing}
    stats::Dict{Symbol, Any}
    
    # Constructor
    function Scheduler(time_slice=0.1, debug=false)
        return new(
            Dict{String, Coroutine}(),
            false,
            time_slice,
            debug,
            nothing,
            Dict{Symbol, Any}(
                :total_coroutines => 0,
                :completed => 0,
                :failed => 0,
                :cycles => 0
            )
        )
    end
end

# Global scheduler instance
const scheduler = Scheduler(0.05, false)

# Debug log
function debug_log(message)
    if scheduler.debug
        styled_print("🔍 $(message)", style=:dim, timestamp=true)
    end
end

# Add a coroutine to the scheduler
function add_coroutine(name, func; priority=NORMAL, id=nothing)
    if id === nothing
        id = string(UInt64(time_ns()))
    end
    
    # Create and add the coroutine
    coroutine = Coroutine(id, name, func, priority)
    scheduler.coroutines[id] = coroutine
    scheduler.stats[:total_coroutines] += 1
    
    styled_print("➕ Added coroutine $(id) ($(name)) with $(priority) priority", style=:cyan)
    return id
end

# Resume a coroutine
function resume_coroutine(coroutine::Coroutine)
    if coroutine.state == COMPLETED || coroutine.state == FAILED
        return false
    end
    
    start_time = time()
    coroutine.state = RUNNING
    scheduler.current_coroutine = coroutine.id
    coroutine.last_run = now()
    coroutine.run_count += 1
    
    debug_log("▶️ Resuming coroutine $(coroutine.id) ($(coroutine.name))")
    
    # Send a value to the channel to resume the coroutine
    try
        if isopen(coroutine.iterator)
            put!(coroutine.iterator, nothing)
            
            # Update statistics
            runtime = time() - start_time
            coroutine.total_runtime += runtime
            debug_log(@sprintf("⏱️ Coroutine %s ran for %.3f seconds", coroutine.id, runtime))
            
            return true
        else
            # Channel is closed, coroutine is completed
            coroutine.state = COMPLETED
            scheduler.stats[:completed] += 1
            styled_print("✅ Coroutine $(coroutine.id) ($(coroutine.name)) completed", style=:green)
            return false
        end
    catch e
        if isa(e, InvalidStateException) && e.state == :closed
            # Channel is closed, coroutine is completed
            coroutine.state = COMPLETED
            scheduler.stats[:completed] += 1
            styled_print("✅ Coroutine $(coroutine.id) ($(coroutine.name)) completed", style=:green)
            return false
        else
            # Unexpected error
            coroutine.state = FAILED
            coroutine.last_error = e
            scheduler.stats[:failed] += 1
            styled_print("❌ Coroutine $(coroutine.id) ($(coroutine.name)) failed: $(e)", style=:red)
            return false
        end
    finally
        scheduler.current_coroutine = nothing
        coroutine.state = coroutine.state == RUNNING ? READY : coroutine.state
    end
end

# Run the scheduler for a specified duration or until all coroutines complete
function run_scheduler(duration=Inf)
    styled_print("🚀 Starting scheduler", style=:bold)
    scheduler.active = true
    start_time = time()
    
    try
        while scheduler.active
            # Check if we've reached the duration limit
            if time() - start_time >= duration
                styled_print("⏱️ Scheduler reached time limit of $(duration) seconds", style=:yellow)
                break
            end
            
            # Check if all coroutines are completed or failed
            active_coroutines = filter(c -> c.state != COMPLETED && c.state != FAILED, values(scheduler.coroutines))
            if isempty(active_coroutines)
                styled_print("✅ All coroutines have completed or failed", style=:green)
                break
            end
            
            # Sort coroutines by priority
            sorted_coroutines = sort(collect(active_coroutines), by=c -> Int(c.priority), rev=true)
            
            # Increment cycle count
            scheduler.stats[:cycles] += 1
            cycle = scheduler.stats[:cycles]
            
            if cycle % 10 == 1
                debug_log("🔄 Scheduler cycle $(cycle) - $(length(sorted_coroutines)) active coroutines")
            end
            
            # Run each coroutine for a time slice
            for coroutine in sorted_coroutines
                # Skip coroutines that are not ready
                if coroutine.state != READY
                    continue
                end
                
                # Resume the coroutine
                resume_coroutine(coroutine)
                
                # Sleep for a tiny amount to let other system tasks run
                sleep(0.001)
            end
            
            # Sleep a tiny bit to prevent CPU spinning
            sleep(0.01)
        end
    catch e
        styled_print("⚠️ Scheduler error: $(e)", style=:bg_red)
        for (trace_idx, frame) in enumerate(stacktrace(catch_backtrace()))
            styled_print("  $(trace_idx). $(frame)", style=:red)
        end
    finally
        scheduler.active = false
        
        # Calculate and display statistics
        total_time = time() - start_time
        styled_print("📊 Scheduler statistics:", style=:magenta)
        styled_print(@sprintf("   - Total runtime: %.2f seconds", total_time), style=:magenta)
        styled_print(@sprintf("   - Total coroutines: %d", scheduler.stats[:total_coroutines]), style=:magenta)
        styled_print(@sprintf("   - Completed: %d (%.1f%%)", 
                    scheduler.stats[:completed], 
                    scheduler.stats[:completed] / scheduler.stats[:total_coroutines] * 100), style=:magenta)
        styled_print(@sprintf("   - Failed: %d (%.1f%%)", 
                    scheduler.stats[:failed], 
                    scheduler.stats[:failed] / scheduler.stats[:total_coroutines] * 100), style=:magenta)
        styled_print(@sprintf("   - Cycles: %d (%.1f cycles/sec)", 
                    scheduler.stats[:cycles], scheduler.stats[:cycles] / total_time), style=:magenta)
        
        # Display individual coroutine statistics
        styled_print("📋 Coroutine details:", style=:cyan)
        sorted_coroutines = sort(collect(values(scheduler.coroutines)), 
                                by=c -> (c.state == COMPLETED ? 0 : (c.state == FAILED ? 1 : 2), c.name))
        
        for coroutine in sorted_coroutines
            status_symbol = coroutine.state == COMPLETED ? "✅" : 
                           (coroutine.state == FAILED ? "❌" : "⏳")
            status_style = coroutine.state == COMPLETED ? :green : 
                          (coroutine.state == FAILED ? :red : :yellow)
            
            styled_print(@sprintf("%s %-20s | %-8s | %3d runs | %7.3f sec | %s", 
                        status_symbol, coroutine.name, coroutine.state, 
                        coroutine.run_count, coroutine.total_runtime,
                        coroutine.last_error === nothing ? "" : "Error: $(coroutine.last_error)"), 
                        style=status_style)
        end
    end
    
    styled_print("🏁 Scheduler stopped", style=:bold)
end

# Helper function to create a cooperative function
function coop_function(func)
    return function(channel)
        while true
            # Run the function
            result = func()
            
            # If the function returns false, stop the coroutine
            if result === false
                break
            end
            
            # Yield control to the scheduler
            take!(channel)
        end
    end
end

# Create a generator coroutine that yields after each value
function create_generator(name, values, delay=0.0; priority=NORMAL)
    return add_coroutine(name, priority=priority) do channel
        for value in values
            styled_print("📤 $(name): Yielding value $(value)", style=:yellow)
            
            if delay > 0
                sleep(delay)
            end
            
            # Yield control to the scheduler
            take!(channel)
        end
        styled_print("📤 $(name): Generator completed", style=:green)
    end
end

# Create a processor coroutine that processes values with a delay
function create_processor(name, work_items, processing_time=0.5; priority=NORMAL, failure_rate=0.0)
    return add_coroutine(name, priority=priority) do channel
        for (i, item) in enumerate(work_items)
            styled_print("🔄 $(name): Processing item $(i)/$(length(work_items)): $(item)", style=:blue)
            
            # Simulate processing time in chunks to demonstrate yielding
            chunks = 5
            chunk_time = processing_time / chunks
            
            for chunk in 1:chunks
                # Simulate some work
                sleep(chunk_time)
                
                # Yield control to allow other coroutines to run
                take!(channel)
                
                styled_print("🔄 $(name): Processing $(i)/$(length(work_items)) - $(chunk*20)%", style=:dim)
            end
            
            # Simulate occasional failures
            if rand() < failure_rate
                error("Simulated random failure while processing item $(item)")
            end
            
            styled_print("✅ $(name): Completed processing item $(i): $(item)", style=:green)
        end
        styled_print("✅ $(name): All processing completed", style=:green)
    end
end

# Create a timer coroutine that triggers at regular intervals
function create_timer(name, interval, count; priority=NORMAL)
    return add_coroutine(name, priority=priority) do channel
        for i in 1:count
            start_time = time()
            
            styled_print("⏰ $(name): Timer $(i)/$(count) triggered", style=:magenta)
            
            # Calculate how long to sleep to maintain the interval
            elapsed = time() - start_time
            sleep_time = max(0.0, interval - elapsed)
            
            if sleep_time > 0
                sleep(sleep_time)
            end
            
            # Yield control to the scheduler
            take!(channel)
        end
        styled_print("⏰ $(name): Timer completed after $(count) intervals", style=:green)
    end
end

# Create an event handler coroutine that responds to events
function create_event_handler(name, events; priority=HIGH)
    return add_coroutine(name, priority=priority) do channel
        for (i, event) in enumerate(events)
            styled_print("🔔 $(name): Handling event $(i)/$(length(events)): $(event["type"])", style=:yellow)
            
            # Process the event based on its type
            if event["type"] == "error"
                styled_print("⚠️ $(name): Error event: $(event["message"])", style=:red)
                sleep(0.3)  # Error events take longer to process
            elseif event["type"] == "warning"
                styled_print("⚠️ $(name): Warning event: $(event["message"])", style=:yellow)
                sleep(0.2)
            elseif event["type"] == "info"
                styled_print("ℹ️ $(name): Info event: $(event["message"])", style=:blue)
                sleep(0.1)
            end
            
            # Yield control to the scheduler
            take!(channel)
            
            styled_print("✅ $(name): Event $(i) handled", style=:green)
        end
        styled_print("✅ $(name): All events handled", style=:green)
    end
end

# Create a worker coroutine that periodically performs a task
function create_worker(name, work_function, iterations; priority=NORMAL, delay=0.5)
    return add_coroutine(name, priority=priority) do channel
        for i in 1:iterations
            styled_print("🔨 $(name): Starting work iteration $(i)/$(iterations)", style=:blue)
            
            # Do the work
            result = work_function(i)
            styled_print("🔨 $(name): Work result: $(result)", style=:blue)
            
            # Pause between work iterations
            if delay > 0 && i < iterations
                sleep(delay)
            end
            
            # Yield control to the scheduler
            take!(channel)
        end
        styled_print("✅ $(name): Work completed after $(iterations) iterations", style=:green)
    end
end

# Set up a demo with multiple coroutines
function run_demo()
    styled_print("🚀 Setting up cooperative multitasking demo", style=:bold)
    
    # Enable debug mode
    scheduler.debug = true
    
    # Create a fast timer
    create_timer("Fast Timer", 0.5, 10, priority=HIGH)
    
    # Create a slow timer
    create_timer("Slow Timer", 1.0, 5, priority=NORMAL)
    
    # Create a worker that calculates fibonacci numbers
    create_worker("Fibonacci Worker", 8, priority=NORMAL, delay=0.3) do i
        n = i + 10  # Calculate larger Fibonacci numbers
        a, b = 0, 1
        for _ in 1:n
            a, b = b, a + b
        end
        return "Fibonacci($(n)) = $(a)"
    end
    
    # Create a worker that calculates prime numbers
    create_worker("Prime Checker", 6, priority=LOW, delay=0.4) do i
        n = i * 10 + 7  # Check larger numbers
        is_prime = true
        if n <= 1
            is_prime = false
        else
            for j in 2:isqrt(n)
                if n % j == 0
                    is_prime = false
                    break
                end
            end
        end
        return "$(n) is " * (is_prime ? "prime" : "not prime")
    end
    
    # Create an event handler for various events
    events = [
        Dict("type" => "info", "message" => "System started"),
        Dict("type" => "warning", "message" => "Disk space low"),
        Dict("type" => "error", "message" => "Network connection failed"),
        Dict("type" => "info", "message" => "New user logged in"),
        Dict("type" => "warning", "message" => "CPU usage high"),
        Dict("type" => "info", "message" => "Backup completed")
    ]
    create_event_handler("System Events", events)
    
    # Create a processor for a batch of items
    items = ["document.docx", "image.jpg", "spreadsheet.xlsx", "presentation.pptx"]
    create_processor("File Processor", items, 0.8, failure_rate=0.2)
    
    # Create a generator that produces values
    values = [10, 20, 30, 40, 50]
    create_generator("Number Generator", values, 0.3)
    
    # Run the scheduler for 15 seconds
    run_scheduler(15.0)
end

# Run the demo
run_demo()
