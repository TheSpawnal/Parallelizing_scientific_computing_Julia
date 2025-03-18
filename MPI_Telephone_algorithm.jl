# telephone_game_mpi.jl
using MPI
using Printf

# Initialize MPI
MPI.Init()

function log_message(rank, message; color=:default)
    # Define colors for better visualization
    colors = Dict(
        :reset     => "\e[0m",
        :bold      => "\e[1m", 
        :red       => "\e[38;5;196m",
        :orange    => "\e[38;5;208m",
        :yellow    => "\e[38;5;226m",
        :green     => "\e[38;5;46m",
        :blue      => "\e[38;5;33m",
        :indigo    => "\e[38;5;57m",
        :violet    => "\e[38;5;165m",
        :cyan      => "\e[38;5;51m",
        :magenta   => "\e[38;5;201m",
        :purple    => "\e[38;5;129m",
        :lime      => "\e[38;5;118m",
        :teal      => "\e[38;5;49m",
        :default   => "\e[0m"
    )
    
    # Assign a color to each rank
    rank_colors = [:red, :orange, :yellow, :green, :blue, :indigo, :violet, :cyan, :magenta, :purple]
    rank_color = rank_colors[mod1(rank+1, length(rank_colors))]
    
    # Format timestamp
    timestamp = @sprintf("%.6f", MPI.Wtime())
    
    # Message color
    msg_color = color == :default ? :reset : color
    
    # Print the message with rank coloring
    println(
        "[$(timestamp)] ", 
        colors[rank_color], "Rank $(rank)", colors[:reset], 
        " ", colors[msg_color], message, colors[:reset]
    )
    flush(stdout)
end

function visualize_ring_topology(nprocs)
    println("\n📋 Ring Topology Visualization:")
    
    colors = Dict(
        :reset  => "\e[0m",
        :green  => "\e[38;5;46m",
        :blue   => "\e[38;5;33m",
    )
    
    for i in 0:(nprocs-1)
        next = (i + 1) % nprocs
        println(colors[:green], "  Rank $i", colors[:reset], 
                " --→ ", 
                colors[:blue], "Rank $next", colors[:reset])
    end
    println()
end

function display_header(nprocs)
    colors = Dict(
        :reset  => "\e[0m",
        :bold   => "\e[1m",
        :blue   => "\e[38;5;33m",
        :yellow => "\e[38;5;226m",
    )
    
    border = string(colors[:blue], repeat("=", 60), colors[:reset])
    title = string(colors[:yellow], colors[:bold], 
                  " 📞 TELEPHONE GAME WITH $nprocs PROCESSES 📞 ", 
                  colors[:reset])
    
    println("\n", border)
    println(title)
    println(border, "\n")
end

function display_summary(initial_value, final_value, nprocs)
    colors = Dict(
        :reset    => "\e[0m",
        :bold     => "\e[1m",
        :yellow   => "\e[38;5;226m",
        :green    => "\e[38;5;46m", 
        :magenta  => "\e[38;5;201m",
        :cyan     => "\e[38;5;51m",
        :blue     => "\e[38;5;33m",
        :pink     => "\e[38;5;199m",
        :lime     => "\e[38;5;118m",
        :red      => "\e[38;5;196m",
    )
    
    println("\n", colors[:bold], colors[:yellow], " 📊 GAME SUMMARY 📊 ", colors[:reset])
    println(colors[:green], "🔢 Initial message: ", colors[:yellow], initial_value, colors[:reset])
    println(colors[:green], "🔢 Final message: ", colors[:magenta], final_value, colors[:reset])
    
    actual_change = final_value - initial_value
    println(colors[:green], "📈 Change: ", colors[:cyan], actual_change, colors[:reset])
    println(colors[:green], "👥 Number of processes: ", colors[:blue], nprocs, colors[:reset])
    
    # Expected change calculation - each process except rank 0 increments once
    expected_change = nprocs - 1
    println(colors[:green], "🧮 Expected change: ", colors[:pink], expected_change, colors[:reset])
    
    # Verification
    if actual_change == expected_change
        println(colors[:lime], "✅ VERIFICATION: Message was correctly transmitted and incremented!", colors[:reset])
    else
        println(colors[:red], "❌ VERIFICATION: Error in transmission! Expected change: $expected_change, Actual: $actual_change", colors[:reset])
    end
end

function run_telephone_game()
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    nprocs = MPI.Comm_size(comm)
    
    # Display info about the game
    if rank == 0
        display_header(nprocs)
        visualize_ring_topology(nprocs)
    end
    
    # Synchronize all processes before starting
    MPI.Barrier(comm)
    
    # Define previous and next rank in the ring
    prev_rank = (rank - 1 + nprocs) % nprocs
    next_rank = (rank + 1) % nprocs
    
    # Message buffer (using an array for MPI send/recv)
    message = [0]  
    
    # Main game logic
    start_time = MPI.Wtime()
    
    if rank == 0
        # Rank 0 generates the initial message
        initial_value = 42  # Could be random: rand(1:100)
        message[1] = initial_value
        
        log_message(rank, "Generated initial message: $(message[1])", color=:yellow)
        
        # Send to first process in the ring
        log_message(rank, "Sending message $(message[1]) to Rank $next_rank", color=:blue)
        MPI.Send(message, comm, dest=next_rank, tag=0)
        
        # Wait for message from last process
        log_message(rank, "Waiting for message from Rank $prev_rank", color=:cyan)
        status = MPI.Recv!(message, comm, source=prev_rank, tag=0)
        final_value = message[1]
        
        # Calculate elapsed time
        elapsed = MPI.Wtime() - start_time
        
        log_message(rank, "Received final message: $final_value from Rank $prev_rank", color=:magenta)
        log_message(rank, "Total time: $(elapsed) seconds", color=:green)
        
        # Display summary
        display_summary(initial_value, final_value, nprocs)
    else
        # Other ranks receive, increment, and forward
        log_message(rank, "Waiting for message from Rank $prev_rank", color=:cyan)
        status = MPI.Recv!(message, comm, source=prev_rank, tag=0)
        received_value = message[1]
        log_message(rank, "Received message: $received_value from Rank $prev_rank", color=:blue)
        
        # Increment the message
        message[1] += 1
        new_value = message[1]
        log_message(rank, "Incremented message to: $new_value", color=:green)
        
        # Simulate some processing time (optional)
        sleep(0.2)
        
        # Send to next process
        log_message(rank, "Sending message $new_value to Rank $next_rank", color=:yellow)
        MPI.Send(message, comm, dest=next_rank, tag=0)
    end
    
    # Final barrier to ensure clean output
    MPI.Barrier(comm)
    
    if rank == 0
        colors = Dict(:cyan => "\e[38;5;51m", :reset => "\e[0m")
        println("\n", colors[:cyan], "Telephone game completed successfully!", colors[:reset])
    end
end

# Run the telephone game
run_telephone_game()

# Finalize MPI
MPI.Finalize()
