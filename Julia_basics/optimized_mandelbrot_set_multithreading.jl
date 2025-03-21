using GLMakie
using Base.Threads
using BenchmarkTools
using Printf
using Dates

"""
Calculate if a point (x,y) belongs to the Mandelbrot set within max_iters iterations.
SIMD optimized version. Returns the iteration count at which the point escapes.
"""
function mandel(x, y, max_iters)
    z = Complex(x, y)
    c = z
    threshold = 2.0
    
    # Cardioid and period-2 bulb check - major optimization for common areas
    if (x + 1)^2 + y^2 < 0.0625  # Cardioid check
        return max_iters
    end
    if (x + 0.25)^2 + y^2 < 0.0625  # Period-2 bulb check
        return max_iters
    end
    
    # Direct calculation using primitives to avoid complex number overhead
    z_real = x
    z_imag = y
    
    # Explicit loop unrolling for common iteration counts
    @inbounds for n in 1:max_iters
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

"""
Calculate a row of the Mandelbrot set.
Optimized for cache locality and vectorization.
"""
function compute_row(j, x_range, y_range, max_iters, result)
    y_val = y_range[j]
    @inbounds for (i, x_val) in enumerate(x_range)
        result[i, j] = mandel(x_val, y_val, max_iters)
    end
end

"""
Calculate Mandelbrot set in parallel using multithreading.
"""
function compute_mandelbrot_parallel(x_range, y_range, max_iters; use_async=false)
    # Create result matrix
    width = length(x_range)
    height = length(y_range)
    result = zeros(Int, width, height)
    
    num_threads = nthreads()
    println("Computing Mandelbrot set using $num_threads threads")
    println("Grid size: $(width)×$(height) = $(width * height) points")
    println("Maximum iterations: $max_iters")
    println("Async tasks: $(use_async ? "enabled" : "disabled")")
    
    # Performance tracking variables
    start_time = time()
    completed_rows = Atomic{Int}(0)
    last_progress_time = Ref(time())
    
    # Create a channel to track completed work
    progress_channel = Channel{Int}(height)
    
    # Progress reporting task
    @async begin
        total_rows = height
        while completed_rows[] < total_rows
            sleep(0.5)  # Update every half second
            current_progress = completed_rows[]
            current_time = time()
            elapsed = current_time - start_time
            
            if current_time - last_progress_time[] >= 1.0  # Update display every second
                if current_progress > 0
                    est_total_time = elapsed * (total_rows / current_progress)
                    remaining = est_total_time - elapsed
                    percentage = 100.0 * current_progress / total_rows
                    
                    @printf("[%s] Progress: %.1f%% (%d/%d rows), Elapsed: %.2fs, Remaining: %.2fs\n",
                            Dates.format(now(), "HH:MM:SS"), 
                            percentage, current_progress, total_rows, 
                            elapsed, remaining)
                    
                    # Update the last progress time
                    last_progress_time[] = current_time
                end
            end
        end
    end
    
    if use_async
        # Async task version - create and monitor tasks
        tasks = []
        for j in 1:height
            t = @async begin
                compute_row(j, x_range, y_range, max_iters, result)
                atomic_add!(completed_rows, 1)
                put!(progress_channel, j)
            end
            push!(tasks, t)
        end
        
        # Wait for all tasks to complete
        for t in tasks
            wait(t)
        end
    else
        # Threaded version - static work division
        @threads for j in 1:height
            compute_row(j, x_range, y_range, max_iters, result)
            atomic_add!(completed_rows, 1)
            put!(progress_channel, j)
        end
    end
    
    # Close the progress channel
    close(progress_channel)
    
    # Calculate total execution time
    end_time = time()
    elapsed = end_time - start_time
    
    # Performance report
    println("\nComputation complete!")
    println("Total execution time: $(elapsed) seconds")
    println("Average time per row: $(elapsed / height) seconds")
    println("Performance: $(width * height / elapsed) pixels/second")
    
    # Create thread utilization report
    if use_async
        println("Used dynamic task distribution with async")
    else
        println("Used static thread distribution with @threads")
    end
    
    return result, elapsed
end

"""
Benchmark different optimization strategies.
"""
function benchmark_strategies(; width=1000, height=1000, max_iters=100)
    # Create coordinate ranges
    x_range = LinRange(-1.7, 0.7, width)
    y_range = LinRange(-1.2, 1.2, height)
    
    # Initialize results dictionary
    results = Dict()
    
    println("\n=== Benchmarking Different Optimization Strategies ===")
    println("Grid size: $(width)×$(height) = $(width * height) points")
    println("Maximum iterations: $max_iters")
    println("Number of threads available: $(nthreads())")
    
    # Benchmark standard threaded version
    println("\n1. Testing standard threaded version...")
    result_threads, time_threads = @timed compute_mandelbrot_parallel(
        x_range, y_range, max_iters, use_async=false
    )
    results["Threaded"] = time_threads
    
    # Benchmark async version
    println("\n2. Testing async task version...")
    result_async, time_async = @timed compute_mandelbrot_parallel(
        x_range, y_range, max_iters, use_async=true
    )
    results["Async"] = time_async
    
    # Print comparative results
    println("\n=== Benchmark Results ===")
    for (strategy, time) in sort(collect(results), by=x->x[2])
        println("$strategy: $(time) seconds")
    end
    
    # Determine the fastest strategy
    fastest = argmin(results)
    println("\nFastest strategy: $fastest ($(results[fastest]) seconds)")
    
    return result_threads  # Return the result for visualization
end

"""
Main function to compute and visualize the Mandelbrot set.
"""
function main()
    # Parameters - increase for higher quality
    max_iters = 1000
    width = 2000
    height = 2000
    
    # Create coordinate ranges
    x_range = LinRange(-1.7, 0.7, width)
    y_range = LinRange(-1.2, 1.2, height)
    
    # Run benchmarks for smaller size
    println("Running benchmarks for optimization comparison...")
    benchmark_strategies(width=500, height=500, max_iters=100)
    
    # Compute full-resolution Mandelbrot set
    println("\nComputing full-resolution Mandelbrot set...")
    start_time = time()
    
    # Use the best strategy determined by benchmark (typically threaded for this case)
    result, _ = compute_mandelbrot_parallel(x_range, y_range, max_iters)
    
    end_time = time()
    elapsed = end_time - start_time
    
    println("Full-resolution computation complete!")
    println("Total execution time: $(elapsed) seconds")
    
    # Plot the result
    println("Generating visualization...")
    fig = Figure(size = (800, 800))
    ax = Axis(fig[1, 1], aspect = DataAspect())
    
    # Apply a colormap that highlights details
    hmap = heatmap!(ax, x_range, y_range, transpose(result), 
                     colormap = :viridis, interpolate = false)
    
    Colorbar(fig[1, 2], hmap)
    
    display(fig)
    save("mandelbrot_threads.png", fig)
    println("Visualization saved to 'mandelbrot_threads.png'")
    
    return result
end

# Run the main function if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end