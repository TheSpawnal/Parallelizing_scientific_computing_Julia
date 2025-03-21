using MPI
using GLMakie
using Printf
using BenchmarkTools

"""
Calculate if a point (x,y) belongs to the Mandelbrot set within max_iters iterations.
Returns the iteration count at which the point escapes, or max_iters if it doesn't escape.
"""
function mandel(x, y, max_iters)
    z = Complex(x, y)
    c = z
    threshold = 2.0
    
    # Loop unrolling for common early escapes
    if (x + 1)^2 + y^2 < 0.0625  # Cardioid check
        return max_iters
    end
    if (x + 0.25)^2 + y^2 < 0.0625  # Period-2 bulb check
        return max_iters
    end
    
    # Main iteration loop with early escape check
    z_real = x
    z_imag = y
    for n in 1:max_iters
        # Manual complex arithmetic to avoid allocations
        z_real_sq = z_real * z_real
        z_imag_sq = z_imag * z_imag
        
        # Early escape check
        if z_real_sq + z_imag_sq > threshold * threshold
            return n - 1
        end
        
        # Update z = z^2 + c
        z_imag = 2 * z_real * z_imag + y
        z_real = z_real_sq - z_imag_sq + x
    end
    
    return max_iters
end


# Calculate Mandelbrot set for a portion of the grid using MPI parallelization.

function compute_mandelbrot_mpi(x_range, y_range, max_iters)
    MPI.Init()
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    nprocs = MPI.Comm_size(comm)
    
    total_rows = length(y_range)
    # Calculate rows per process, ensuring all rows are assigned
    rows_per_proc = div(total_rows, nprocs)
    extra_rows = total_rows % nprocs
    
    # Calculate this process's portion of rows
    start_row = rank * rows_per_proc + min(rank, extra_rows) + 1
    num_rows = rows_per_proc + (rank < extra_rows ? 1 : 0)
    end_row = start_row + num_rows - 1
    
    local_start_time = time()
    
    # Preallocate the results for this process
    local_result = zeros(Int, length(x_range), num_rows)
    
    # Log start of computation for this process
    if rank == 0
        println("Starting Mandelbrot computation with $nprocs processes")
        println("Grid size: $(length(x_range))×$(length(y_range)) = $(length(x_range) * length(y_range)) points")
        println("Maximum iterations: $max_iters")
    end
    MPI.Barrier(comm)
    println("Process $rank computing rows $start_row to $end_row ($(num_rows) rows)")
    
    # Compute the Mandelbrot set for this process's portion
    for (local_j, global_j) in enumerate(start_row:end_row)
        y_val = y_range[global_j]
        for (i, x_val) in enumerate(x_range)
            local_result[i, local_j] = mandel(x_val, y_val, max_iters)
        end
        
        # Log progress every 10% of rows
        if local_j % max(1, div(num_rows, 10)) == 0
            progress = (local_j / num_rows) * 100
            elapsed = time() - local_start_time
            remaining = elapsed * (num_rows / local_j - 1)
            @printf("Process %d: %.1f%% complete, elapsed: %.2fs, est. remaining: %.2fs\n", 
                    rank, progress, elapsed, remaining)
        end
    end
    
    local_end_time = time()
    local_elapsed = local_end_time - local_start_time
    println("Process $rank finished in $(local_elapsed) seconds")
    
    # All processes send their results to rank 0
    if rank == 0
        # Preallocate the full result matrix
        global_result = zeros(Int, length(x_range), length(y_range))
        
        # Copy rank 0's portion to the global result
        for (local_j, global_j) in enumerate(start_row:end_row)
            global_result[:, global_j] = local_result[:, local_j]
        end
        
        # Receive data from other processes
        for p in 1:nprocs-1
            p_start_row = p * rows_per_proc + min(p, extra_rows) + 1
            p_num_rows = rows_per_proc + (p < extra_rows ? 1 : 0)
            p_end_row = p_start_row + p_num_rows - 1
            
            # Receive the data from process p
            recv_buffer = Array{Int}(undef, length(x_range), p_num_rows)
            MPI.Recv!(recv_buffer, p, 0, comm)
            
            # Copy the received data to the global result
            for (local_j, global_j) in enumerate(p_start_row:p_end_row)
                global_result[:, global_j] = recv_buffer[:, local_j]
            end
        end
        
        return global_result, local_elapsed
    else
        # Send this process's portion to rank 0
        MPI.Send(local_result, 0, 0, comm)
        return nothing, local_elapsed
    end
end

"""
Main function to compute and visualize the Mandelbrot set.
"""
function main()
    # Parameters
    max_iters = 1000
    width = 2000
    height = 2000
    x_min, x_max = -1.7, 0.7
    y_min, y_max = -1.2, 1.2
    
    # Create coordinate ranges
    x_range = LinRange(x_min, x_max, width)
    y_range = LinRange(y_min, y_max, height)
    
    # Start timing
    global_start_time = time()
    
    # Compute the Mandelbrot set using MPI
    result, local_elapsed = compute_mandelbrot_mpi(x_range, y_range, max_iters)
    
    MPI.Finalize()
    
    # Only rank 0 will have a valid result to plot
    if result !== nothing
        global_end_time = time()
        global_elapsed = global_end_time - global_start_time
        
        println("\nComputation complete!")
        println("Total execution time: $(global_elapsed) seconds")
        println("Process 0 computation time: $(local_elapsed) seconds")
        println("Visualization efficiency: $(local_elapsed / global_elapsed * 100)%")
        
        # Plot the result
        println("Generating visualization...")
        fig = Figure(size = (800, 800))
        ax = Axis(fig[1, 1], aspect = DataAspect())
        
        # Apply a colormap that highlights details
        hmap = heatmap!(ax, x_range, y_range, transpose(result), 
                         colormap = :viridis, interpolate = false)
        
        Colorbar(fig[1, 2], hmap)
        
        display(fig)
        save("mandelbrot_mpi.png", fig)
        println("Visualization saved to 'mandelbrot_mpi.png'")
    end
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end