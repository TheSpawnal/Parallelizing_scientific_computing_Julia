# Flexible Telephone Game Implementation
# Supports any number of workers with dynamic configuration
# Run `using Distributed; addprocs(N)` before executing this code



using Distributed
using Printf
using Random
using Dates

# Define these functions and constants on all workers
@everywhere begin
    using Distributed
    using Printf
    using Dates
    
    # Vibrant color palette with many options
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
        :gold      => "\e[38;5;220m",
        :lime      => "\e[38;5;118m",
        :teal      => "\e[38;5;49m",
        :lavender  => "\e[38;5;183m",
        :coral     => "\e[38;5;209m",
        :turquoise => "\e[38;5;45m",
        :maroon    => "\e[38;5;124m",
        :olive     => "\e[38;5;142m",
        :navy      => "\e[38;5;21m",
        :mint      => "\e[38;5;121m",
        :salmon    => "\e[38;5;210m",
        :plum      => "\e[38;5;96m",
        :sky       => "\e[38;5;117m",
        :tan       => "\e[38;5;180m",
        :bg_black  => "\e[48;5;16m",
        :bg_blue   => "\e[48;5;27m",
        :bg_purple => "\e[48;5;93m"
    )
    
    # Emoji indicators for different message types
    const EMOJIS = Dict(
        :generate => "🎲",
        :receive  => "📩",
        :process  => "🔄",
        :send     => "📤",
        :complete => "🏁",
        :final    => "📬",
        :error    => "❌",
        :success  => "✅"
    )
    
    # Function to print colorful messages with timestamp and worker ID
    function log_message(message; type=:info, worker_id=nothing)
        # Get actual worker ID if not provided
        if worker_id === nothing
            worker_id = myid() - 1  # Adjust for process ID (main process is 1)
        end
        
        # Define colors for different message types
        type_colors = Dict(
            :info     => :blue,
            :receive  => :green,
            :send     => :yellow,
            :process  => :cyan,
            :complete => :lime,
            :error    => :red,
            :generate => :gold,
            :final    => :magenta
        )
        
        # Worker-specific colors (consistent for each worker)
        worker_colors = [
            :red, :orange, :yellow, :green, :blue, :indigo, :violet, 
            :pink, :cyan, :magenta, :purple, :lime, :coral, :turquoise, 
            :teal, :lavender, :maroon, :olive, :navy, :mint, :salmon, 
            :plum, :sky, :tan
        ]
        
        # Select colors
        worker_color = worker_colors[mod1(worker_id, length(worker_colors))]
        message_color = get(type_colors, type, :reset)
        
        # Get emoji for message type
        emoji = get(EMOJIS, type, "💬")
        
        # Format timestamp
        timestamp = Dates.format(now(), "HH:MM:SS.sss")
        
        # Compose the message
        formatted = string(
            "[", timestamp, "] ",
            COLORS[worker_color], COLORS[:bold], "W$(worker_id)", COLORS[:reset],
            " ", emoji, " ",
            COLORS[message_color], message, COLORS[:reset]
        )
        
        # Print and flush to ensure immediate display
        println(formatted)
        flush(stdout)
        
        return nothing
    end
    
    # Worker function to process a message in the telephone game
    function handle_message(message, from_worker, worker_id, num_workers)
        # Log receiving the message
        log_message("Received message: $message from Worker $from_worker", 
                   type=:receive, worker_id=worker_id)
        
        # Process the message (increment by 1)
        new_message = message + 1
        log_message("Incremented message to: $new_message", 
                   type=:process, worker_id=worker_id)
        
        # Determine the next worker in the ring
        next_worker = worker_id == num_workers ? 1 : worker_id + 1
        
        # Log sending the message
        log_message("Sending message to Worker $next_worker", 
                   type=:send, worker_id=worker_id)
        
        return new_message, next_worker
    end
end

# Print a fancy header for the game
function print_game_header(num_workers)
    # Create colorful title with background
    title = string(
        COLORS[:bg_purple], COLORS[:bold], COLORS[:yellow],
        " 📞 TELEPHONE GAME WITH $num_workers WORKERS 📞 ",
        COLORS[:reset]
    )
    
    # Create a rainbow border
    rainbow_colors = [:red, :orange, :yellow, :green, :blue, :indigo, :violet]
    border = ""
    
    for i in 1:60
        color = rainbow_colors[mod1(i, length(rainbow_colors))]
        border *= COLORS[color] * "=" * COLORS[:reset]
    end
    
    # Print the header
    println("\n", border)
    println(title)
    println(border, "\n")
end

# Visualize the ring topology
function visualize_ring_topology(num_workers)
    println(COLORS[:cyan], COLORS[:bold], "\n📋 Ring Topology Visualization:", COLORS[:reset])
    
    # Define colors for connections
    colors = [
        :red, :orange, :yellow, :green, :blue, :indigo, :violet,
        :pink, :cyan, :magenta, :purple, :lime, :coral, :turquoise
    ]
    
    # Draw the connections
    for i in 1:num_workers
        next = i == num_workers ? 1 : i + 1
        
        # Select different colors for each worker
        from_color = colors[mod1(i, length(colors))]
        to_color = colors[mod1(next, length(colors))]
        
        # Draw the connection with arrow
        println(
            "   ", COLORS[from_color], COLORS[:bold], "Worker $i", COLORS[:reset],
            " ", COLORS[:yellow], "──→", COLORS[:reset], " ",
            COLORS[to_color], COLORS[:bold], "Worker $next", COLORS[:reset]
        )
    end
    println()
end

# Print a summary of the game results
function print_game_summary(initial_message, final_message, num_workers)
    println("\n", COLORS[:bg_blue], COLORS[:bold], COLORS[:yellow], " 📊 TELEPHONE GAME RESULTS 📊 ", COLORS[:reset])
    
    # Calculate the expected change based on the ring
    expected_change = num_workers
    actual_change = final_message - initial_message
    
    # Print the details with colorful formatting
    println(COLORS[:green], "🔢 Initial message: ", COLORS[:yellow], initial_message, COLORS[:reset])
    println(COLORS[:green], "🔢 Final message: ", COLORS[:magenta], final_message, COLORS[:reset])
    println(COLORS[:green], "📈 Total change: ", COLORS[:cyan], actual_change, COLORS[:reset])
    println(COLORS[:green], "👥 Number of workers: ", COLORS[:blue], num_workers, COLORS[:reset])
    println(COLORS[:green], "🧮 Expected change: ", COLORS[:pink], expected_change, COLORS[:reset])
    
    # Verify the result
    if actual_change == expected_change
        println(COLORS[:lime], "✅ SUCCESS: Message was correctly transmitted and incremented!", COLORS[:reset])
    else
        println(COLORS[:red], "❌ ERROR: Incorrect transmission! Expected +$expected_change, got +$actual_change", COLORS[:reset])
    end
end

# Main function to run the telephone game
function run_telephone_game(num_workers=4; initial_message=nothing)
    # Ensure we have enough workers
    if nprocs() <= num_workers
        addprocs(num_workers - nprocs() + 1)
        @info "Added workers. Now running with $(nprocs()) processes."
    end
    
    print_game_header(num_workers)
    
    # Generate a random message if not provided
    if initial_message === nothing
        initial_message = rand(1:100)
    end
    
    println(COLORS[:purple], "📣 Starting telephone game with $num_workers workers...", COLORS[:reset])
    println(COLORS[:teal], "🎲 Initial message: $initial_message", COLORS[:reset])
    
    visualize_ring_topology(num_workers)
    
    # Create a channel for the final result
    result_channel = RemoteChannel(() -> Channel{Int}(1))
    
    # Start the telephone game
    @sync begin
        # Set up all worker processes with channels for communication
        channels = Dict()
        
        for i in 1:num_workers
            next_worker = i == num_workers ? 1 : i + 1
            channels[i] = RemoteChannel(() -> Channel{Int}(1))
        end
        
        # Start worker 1 (the initiator)
        @async begin
            # Worker 1 generates and sends the message
            message = initial_message
            worker_id = 1
            
            log_message("Generated initial message: $message", 
                       type=:generate, worker_id=worker_id)
            
            # Send to next worker
            next_worker = 2
            log_message("Sending message to Worker $next_worker", 
                       type=:send, worker_id=worker_id)
            
            # Put the message in the channel for the next worker
            put!(channels[next_worker], message)
            
            # Wait for the message to come back
            final_message = take!(channels[1])
            
            log_message("Received final message: $final_message from Worker $num_workers", 
                       type=:final, worker_id=worker_id)
            log_message("Telephone game completed!", 
                       type=:complete, worker_id=worker_id)
            
            # Send the result to the main process
            put!(result_channel, final_message)
        end
        
        # Start all other workers
        for worker_id in 2:num_workers
            @async begin
                # Determine previous and next worker in the ring
                prev_worker = worker_id - 1
                next_worker = worker_id == num_workers ? 1 : worker_id + 1
                
                # Receive message from previous worker
                message = take!(channels[worker_id])
                
                # Process the message
                new_message = message + 1
                log_message("Received message: $message from Worker $prev_worker", 
                           type=:receive, worker_id=worker_id)
                log_message("Incremented message to: $new_message", 
                           type=:process, worker_id=worker_id)
                
                # Send to next worker
                log_message("Sending message to Worker $next_worker", 
                           type=:send, worker_id=worker_id)
                put!(channels[next_worker], new_message)
            end
        end
    end
    
    # Get the final result
    final_message = take!(result_channel)
    
    # Display the summary
    print_game_summary(initial_message, final_message, num_workers)
    
    return final_message
end

# Run the telephone game with dynamic number of workers
println("Starting the Telephone Game...")
run_telephone_game(6)  # Change the number to run with different worker counts
