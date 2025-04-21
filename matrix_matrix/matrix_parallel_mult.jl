@everywhere using Logging, Dates, Printf

# Custom colorful logger for performance tracking
@everywhere struct ColorfulLogger <: AbstractLogger
    min_level::LogLevel
end

@everywhere function Logging.handle_message(logger::ColorfulLogger, level, message, _module, group, id, file, line; kwargs...)
    color = if level == Logging.Info
        "\e[1;36m"  # Bright Cyan
    elseif level == Logging.Warn
        "\e[1;33m"  # Bright Yellow
    elseif level == Logging.Error
        "\e[1;31m"  # Bright Red
    elseif level == Logging.Debug
        "\e[1;35m"  # Bright Magenta
    else
        "\e[1;32m"  # Bright Green
    end
    
    timestamp = Dates.format(now(), "HH:MM:SS.sss")
    prefix = "[$timestamp][$level]"
    
    # Add worker ID information when running on workers
    worker_info = myid() == 1 ? "MASTER" : "WORKER-$(myid())"
    prefix = "[$worker_info]$prefix"
    
    println(color, prefix, " ", message, "\e[0m")
end

# Define required logger interface methods
@everywhere Logging.shouldlog(logger::ColorfulLogger, level, _module, group, id) = level >= logger.min_level
@everywhere Logging.min_enabled_level(logger::ColorfulLogger) = logger.min_level
@everywhere Logging.catch_exceptions(logger::ColorfulLogger) = false

@everywhere colorful_logger = ColorfulLogger(Logging.Info)

# Metric tracking function
@everywhere function track_operation(operation, data_size, start_time)
    duration = (time_ns() - start_time) / 1e9  # Convert to seconds
    data_mb = data_size / (1024 * 1024)  # Convert to MB
    throughput = data_mb / duration  # MB/s
    
    @info "METRICS" operation duration=@sprintf("%.6f s", duration) data_size=@sprintf("%.2f MB", data_mb) throughput=@sprintf("%.2f MB/s", throughput)
end

function matmul_dist_3!(C, A, B)
    with_logger(colorful_logger) do
        m = size(C, 1)
        n = size(C, 2)
        l = size(A, 2)
        
        @assert size(A, 1) == m
        @assert size(B, 2) == n
        @assert size(B, 1) == l
        @assert mod(m, nworkers()) == 0
        
        P = nworkers()
        rows_per_worker = m ÷ P
        
        @info "Starting distributed matrix multiplication" matrix_size="$(m)×$(n)" workers=P rows_per_worker=rows_per_worker
        
        # Split the work among workers
        global_start = time_ns()
        
        @sync begin
            for (iw, w) in enumerate(workers())
                # Calculate row range for this worker
                start_row = (iw - 1) * rows_per_worker + 1
                end_row = iw * rows_per_worker
                
                @info "Dispatching work" worker=w row_range="$(start_row):$(end_row)"
                
                # Get the rows for this worker
                rows = start_row:end_row
                A_rows = A[rows, :]
                
                # Track data sent to worker
                data_size_sent = sizeof(A_rows) + sizeof(B)
                
                # Spawn task on worker
                ftr = @spawnat w begin
                    # Local worker logging
                    worker_start = time_ns()
                    @info "Received data" A_rows_size=@sprintf("%.2f MB", sizeof(A_rows)/(1024*1024)) B_size=@sprintf("%.2f MB", sizeof(B)/(1024*1024))
                    
                    # Create result matrix for this worker's rows
                    local_rows = size(A_rows, 1)
                    C_part = zeros(eltype(C), local_rows, n)
                    
                    # Compute the matrix multiplication for assigned rows
                    compute_start = time_ns()
                    for i in 1:local_rows
                        for j in 1:n
                            for k in 1:l
                                @inbounds C_part[i, j] += A_rows[i, k] * B[k, j]
                            end
                        end
                    end
                    
                    # Track computation metrics
                    compute_time = (time_ns() - compute_start) / 1e9
                    flops = local_rows * n * l * 2  # multiply-add counts as 2 operations
                    gflops = flops / (compute_time * 1e9)
                    
                    @info "Computation complete" compute_time=@sprintf("%.6f s", compute_time) gflops=@sprintf("%.2f GFLOPS", gflops)
                    
                    # Track return data size
                    return_data_size = sizeof(C_part)
                    @info "Sending results back" result_size=@sprintf("%.2f MB", return_data_size/(1024*1024))
                    
                    # Total worker execution time
                    total_worker_time = (time_ns() - worker_start) / 1e9
                    @info "Worker task complete" total_time=@sprintf("%.6f s", total_worker_time)
                    
                    # Return result
                    C_part
                end
                
                # Asynchronously update C with results when they arrive
                @async begin
                    recv_start = time_ns()
                    result = fetch(ftr)
                    recv_time = (time_ns() - recv_start) / 1e9
                    
                    @info "Received results from worker" worker=w time=@sprintf("%.6f s", recv_time) 
                    
                    # Update C
                    C[start_row:end_row, :] = result
                    
                    @info "Updated result matrix" rows="$(start_row):$(end_row)"
                end
            end
        end
        
        total_time = (time_ns() - global_start) / 1e9
        total_flops = m * n * l * 2
        total_gflops = total_flops / (total_time * 1e9)
        
        @info "Matrix multiplication complete" total_time=@sprintf("%.6f s", total_time) effective_gflops=@sprintf("%.2f GFLOPS", total_gflops)
        
        return C
    end
end

# Enhanced performance measurement function
function measure_performance(func, args...; trials=5)
    with_logger(colorful_logger) do
        P = nworkers()
        
        # Run sequential for comparison
        @info "===== STARTING SEQUENTIAL BENCHMARK =====" 
        seq_times = Float64[]
        for i in 1:trials
            @info "Sequential trial $i/$trials"
            C_seq = similar(args[1])
            start_time = time_ns()
            matmul_seq!(C_seq, args[2], args[3])
            elapsed = (time_ns() - start_time) / 1e9
            push!(seq_times, elapsed)
            GC.gc()
        end
        T1 = minimum(seq_times)
        
        # Run parallel
        @info "===== STARTING PARALLEL BENCHMARK =====" workers=P
        par_times = Float64[]
        for i in 1:trials
            @info "Parallel trial $i/$trials"
            C_par = similar(args[1])
            start_time = time_ns()
            func(C_par, args[2], args[3])
            elapsed = (time_ns() - start_time) / 1e9
            push!(par_times, elapsed)
            GC.gc()
        end
        TP = minimum(par_times)
        
        # Calculate metrics
        speedup = T1/TP
        efficiency = 100 * speedup / P
        
        # Print performance results
        @info "===== PERFORMANCE SUMMARY =====" 
        @info "Sequential time: $(round(T1, digits=6)) seconds"
        @info "Parallel time: $(round(TP, digits=6)) seconds"
        @info "Speedup: $(round(speedup, digits=2))x"
        @info "Optimal speedup: $(P)x"
        @info "Efficiency: $(round(efficiency, digits=2))%"
        
        return Dict(
            "seq_time" => T1,
            "par_time" => TP,
            "speedup" => speedup,
            "optimal" => P,
            "efficiency" => efficiency
        )
    end
end