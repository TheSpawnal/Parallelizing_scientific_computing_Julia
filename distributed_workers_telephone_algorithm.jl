# Fixed Telephone Game Implementation in Julia
# Corrects the verification logic and status monitoring issue

using Distributed

# Only add workers if needed - prevents worker duplication errors
if nprocs() <= 1
    addprocs(5)  # Add 5 workers for our game
    @info "Added workers. Now running with $(nprocs()) processes including the main process."
end

# Define colors and constants ONLY ONCE on all workers
@everywhere begin
    using Dates
    using Printf
    
    # Define colors only if not already defined
    if !@isdefined(COLORS)
        const COLORS = Dict(
            :reset     => "\e[0m",
            :bold      => "\e[1m", 
            :red       => "\e[38;5;196m",
            :orange    => "\e[38;5;208m",
            :yellow    => "\e[38;5;226m",
            :green     => "\e[38;5;46m",
            :blue      => "\e[38;5;33m",
            :indigo    => "\e[38;5;57m",
            :violet    => "\e[38;5;165m",
            :pink      => "\e[38;5;199m",
            :cyan      => "\e[38;5;51m",
            :magenta   => "\e[38;5;201m",
            :purple    => "\e[38;5;129m",
            :lime      => "\e[38;5;118m",
            :teal      => "\e[38;5;49m"
        )
    end
    
    # Function for colorful logging with timestamp
    function log_message(message; color=:reset, worker_id=nothing)
        if worker_id === nothing
            worker_id = myid() - 1  # Worker ID is process ID - 1 (main process is 1)
        end
        
        # Worker colors - use deterministic color based on worker ID
        worker_colors = [:red, :orange, :yellow, :green, :blue, :indigo, 
                        :violet, :pink, :cyan, :magenta, :purple, :lime]
        
        worker_color = worker_colors[mod1(worker_id, length(worker_colors))]
        
        # Format timestamp
        timestamp = Dates.format(now(), "HH:MM:SS.sss")
        
        # Format the message
        formatted = string(
            "[", timestamp, "] ", 
            COLORS[worker_color], "Worker ", worker_id, COLORS[:reset], 
            " ", COLORS[color], message, COLORS[:reset]
        )
        
        # Print with flush to ensure immediate display
        println(formatted)
        flush(stdout)
    end
end

# Function to display a decorative header for the game
function display_header(num_workers)
    border = string(COLORS[:blue], repeat("=", 60), COLORS[:reset])
    title = string(COLORS[:yellow], COLORS[:bold], 
                  " 📞 TELEPHONE GAME WITH $num_workers WORKERS 📞 ", 
                  COLORS[:reset])
    
    println("\n", border)
    println(title)
    println(border, "\n")
end

# Visualize the ring topology
function visualize_ring(num_workers)
    println(COLORS[:cyan], "\n📋 Ring Topology Visualization:", COLORS[:reset])
    
    for i in 1:num_workers
        next = i == num_workers ? 1 : i + 1
        println(COLORS[:green], "  Worker $i", COLORS[:reset], 
                " --→ ", 
                COLORS[:blue], "Worker $next", COLORS[:reset])
    end
    println()
end

# Print a summary of the game results
function display_summary(initial_message, final_message, num_workers)
    println("\n", COLORS[:bold], COLORS[:yellow], " 📊 GAME SUMMARY 📊 ", COLORS[:reset])
    println(COLORS[:green], "🔢 Initial message: ", COLORS[:yellow], initial_message, COLORS[:reset])
    println(COLORS[:green], "🔢 Final message: ", COLORS[:magenta], final_message, COLORS[:reset])
    println(COLORS[:green], "📈 Change: ", COLORS[:cyan], final_message - initial_message, COLORS[:reset])
    println(COLORS[:green], "👥 Number of workers: ", COLORS[:blue], num_workers, COLORS[:reset])
    
    # Expected change calculation - FIXED: The message is incremented (num_workers - 1) times
    # Since the first worker doesn't increment (it only generates the initial message)
    expected_change = num_workers - 1
    println(COLORS[:green], "🧮 Expected change: ", COLORS[:pink], expected_change, COLORS[:reset])
    
    # Verification
    if final_message - initial_message == expected_change
        println(COLORS[:lime], "✅ VERIFICATION: Message was correctly transmitted and incremented!", COLORS[:reset])
    else
        println(COLORS[:red], "❌ VERIFICATION: Error in transmission! Expected change: $expected_change, Actual: $(final_message - initial_message)", COLORS[:reset])
    end
end

# Main function to run the telephone game
function run_telephone_game(num_workers=5, initial_message=nothing)
    # Ensure we don't exceed available workers
    actual_workers = min(num_workers, nprocs() - 1)
    
    if actual_workers < num_workers
        @warn "Only $actual_workers workers available. Using $actual_workers instead of requested $num_workers."
        num_workers = actual_workers
    end
    
    # Display header
    display_header(num_workers)
    
    # Generate random message if not provided
    if initial_message === nothing
        initial_message = rand(1:100)
    end
    
    println(COLORS[:purple], "📣 Initializing telephone game with workers...", COLORS[:reset])
    println(COLORS[:teal], "🎲 Initial message: $initial_message", COLORS[:reset])
    
    # Show the ring topology
    visualize_ring(num_workers)
    
    # Create a channel for the final result with timeout capability
    result_channel = RemoteChannel(() -> Channel{Int}(1))
    
    # Create worker process IDs (actual process IDs to use)
    worker_pids = workers()[1:num_workers]
    
    # Main task that runs the game
    game_task = @async begin
        try
            # Create channels for worker communication
            message_channels = Dict()
            for i in 1:num_workers
                next_idx = i == num_workers ? 1 : i + 1
                # Each channel connects worker i to worker next_idx
                message_channels[i] = RemoteChannel(() -> Channel{Int}(1))
            end
            
            # Start the first worker (initiator)
            @async remotecall_wait(worker_pids[1]) do
                try
                    worker_id = 1
                    log_message("Starting as initiator", color=:green, worker_id=worker_id)
                    
                    # Generate initial message
                    message = initial_message
                    log_message("Generated message: $message", color=:yellow, worker_id=worker_id)
                    
                    # Send to next worker
                    next_worker = 2
                    log_message("Sending to Worker $next_worker", color=:blue, worker_id=worker_id)
                    
                    # Put message in channel of next worker
                    try
                        put!(message_channels[next_worker], message)
                        log_message("Successfully sent to Worker $next_worker", color=:green, worker_id=worker_id)
                    catch e
                        log_message("Error sending: $e", color=:red, worker_id=worker_id)
                        rethrow(e)
                    end
                    
                    # Wait for message to come back from last worker
                    log_message("Waiting for message to return", color=:cyan, worker_id=worker_id)
                    
                    # Set a timeout for the take operation
                    final_message = nothing
                    
                    try
                        # Use timeout for take! to prevent deadlock
                        t = @async take!(message_channels[1])
                        
                        # Wait with timeout
                        for i in 1:25  # Check every 1 second for 25 seconds max
                            if istaskdone(t)
                                final_message = fetch(t)
                                break
                            end
                            sleep(1)
                        end
                        
                        if final_message === nothing
                            log_message("Timeout waiting for final message", color=:red, worker_id=worker_id)
                        else
                            log_message("Received final message: $final_message", color=:magenta, worker_id=worker_id)
                            put!(result_channel, final_message)
                        end
                    catch e
                        log_message("Error receiving final message: $e", color=:red, worker_id=worker_id)
                    end
                catch e
                    @error "Worker 1 error: $e"
                end
            end
            
            # Start the middle workers (2 to num_workers)
            for i in 2:num_workers
                worker_pid = worker_pids[i]
                
                @async remotecall_wait(worker_pid) do
                    try
                        worker_id = i
                        prev_worker = i - 1
                        next_worker = i == num_workers ? 1 : i + 1
                        
                        log_message("Starting", color=:green, worker_id=worker_id)
                        
                        # Set a timeout for the take operation
                        message = nothing
                        
                        try
                            # Use timeout for take! to prevent deadlock
                            t = @async take!(message_channels[i])
                            
                            # Wait with timeout
                            for j in 1:20  # Check every 1 second for 20 seconds max
                                if istaskdone(t)
                                    message = fetch(t)
                                    break
                                end
                                sleep(1)
                            end
                            
                            if message === nothing
                                log_message("Timeout waiting for message", color=:red, worker_id=worker_id)
                                return
                            end
                        catch e
                            log_message("Error receiving message: $e", color=:red, worker_id=worker_id)
                            return
                        end
                        
                        log_message("Received message: $message from Worker $prev_worker", 
                                   color=:blue, worker_id=worker_id)
                        
                        # Increment message
                        new_message = message + 1
                        log_message("Incremented message to: $new_message", 
                                   color=:green, worker_id=worker_id)
                        
                        # Send to next worker
                        log_message("Sending to Worker $next_worker", 
                                   color=:yellow, worker_id=worker_id)
                        
                        try
                            put!(message_channels[next_worker], new_message)
                            log_message("Successfully sent to Worker $next_worker", 
                                      color=:green, worker_id=worker_id)
                        catch e
                            log_message("Error sending to next worker: $e", 
                                      color=:red, worker_id=worker_id)
                        end
                    catch e
                        @error "Worker $i error: $e"
                    end
                end
            end
            
            # Wait for the result with timeout
            final_message = nothing
            
            try
                # Poll for result with timeout
                for i in 1:30  # Check every 1 second for 30 seconds max
                    # Try to take from the result channel, but don't block
                    if isready(result_channel)
                        final_message = take!(result_channel)
                        break
                    end
                    
                    sleep(1)
                end
            catch e
                @error "Error waiting for final result: $e"
            end
            
            # Display summary if we got a result
            if final_message !== nothing
                display_summary(initial_message, final_message, num_workers)
                return final_message
            else
                println(COLORS[:red], "❌ Game timed out. Message did not complete the ring.", COLORS[:reset])
                return nothing
            end
        catch e
            @error "Game task error: $e"
            return nothing
        finally
            # Clean up resources
            try
                close(result_channel)
            catch; end
        end
    end
    
    # Wait for the game to complete with a timeout
    timeout_seconds = 30
    result = nothing
    
    # Create a timeout task
    timeout_task = @async begin
        sleep(timeout_seconds)
        if !istaskdone(game_task)
            @warn "Game has been running for $timeout_seconds seconds. Forcing termination."
            try
                schedule(game_task, InterruptException(), error=true)
            catch; end
        end
    end
    
    # Wait for completion or timeout
    try
        result = fetch(game_task)
    catch e
        @error "Game execution error: $e"
    end
    
    # Cancel timeout task if needed
    if !istaskdone(timeout_task)
        try
            schedule(timeout_task, InterruptException(), error=true)
        catch; end
    end
    
    println(COLORS[:cyan], "Game completed with result: ", 
           result === nothing ? "Failed" : result, COLORS[:reset])
    
    return result
end

# Run the telephone game
println("Starting the Telephone Game...")
result = run_telephone_game(5)