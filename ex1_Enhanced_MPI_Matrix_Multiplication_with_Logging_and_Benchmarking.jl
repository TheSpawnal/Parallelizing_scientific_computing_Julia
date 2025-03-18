# ex1.jl - Enhanced MPI Matrix Multiplication with Logging and Benchmarking
using MPI
using Printf
using Statistics


MPI.Init()

function matrix_to_string(A, max_elements=5)
    m, n = size(A)
    
    # If matrix is too large, print a truncated version
    if m > max_elements || n > max_elements
        rows = min(max_elements, m)
        cols = min(max_elements, n)
        result = "$(m)×$(n) matrix (showing $(rows)×$(cols)):\n"
        
        for i in 1:rows
            row_str = ""
            for j in 1:cols
                row_str *= @sprintf("%.2f ", A[i,j])
            end
            # Add ellipsis if we're not showing all columns
            if cols < n
                row_str *= "... "
            end
            result *= row_str * "\n"
        end
        
        # Add ellipsis if we're not showing all rows
        if rows < m
            result *= "...\n"
        end
        return result
    else
        # Print the whole matrix for small matrices
        result = "$(m)×$(n) matrix:\n"
        for i in 1:m
            for j in 1:n
                result *= @sprintf("%.2f ", A[i,j])
            end
            result *= "\n"
        end
        return result
    end
end

# Log messages with rank and timestamp
function log_message(comm, message)
    rank = MPI.Comm_rank(comm)
    time_str = @sprintf("%.6f", MPI.Wtime())
    println("Rank $(rank) [$(time_str)s]: $(message)")
end

function matmul_mpi_3!(C, A, B)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    nprocs = MPI.Comm_size(comm)
    
    # Start timing
    start_time = MPI.Wtime()
    
    if rank == 0
        log_message(comm, "Starting matrix multiplication")
        log_message(comm, "Matrix A: $(size(A,1))×$(size(A,2))")
        log_message(comm, "Matrix B: $(size(B,1))×$(size(B,2))")
        
        # Only rank 0 has the actual matrices initially
        N = size(A, 1)
        @assert N % nprocs == 0 "Matrix size $(N) must be divisible by number of processes $(nprocs)"
        rows_per_proc = div(N, nprocs)
        
        log_message(comm, "Each process will handle $(rows_per_proc) rows")
        
        # Visualize small portions of input matrices
        if N <= 20
            log_message(comm, "Matrix A:\n$(matrix_to_string(A))")
            log_message(comm, "Matrix B:\n$(matrix_to_string(B))")
        else
            log_message(comm, "Matrix A preview:\n$(matrix_to_string(A))")
            log_message(comm, "Matrix B preview:\n$(matrix_to_string(B))")
        end
        
        # Process own chunk (rank 0's portion - first rows_per_proc rows)
        chunk_start = MPI.Wtime()
        log_message(comm, "Computing rows 1:$(rows_per_proc)")
        
        for i in 1:rows_per_proc
            for j in 1:N
                C[i, j] = 0
                for k in 1:N
                    C[i, j] += A[i, k] * B[k, j]
                end
            end
        end
        
        chunk_time = MPI.Wtime() - chunk_start
        log_message(comm, "Finished computing my chunk in $(chunk_time) seconds")
        
        # Send data to other processes
        send_start = MPI.Wtime()
        
        for p in 1:(nprocs-1)
            start_row = p * rows_per_proc + 1
            end_row = (p + 1) * rows_per_proc
            
            log_message(comm, "Sending data to rank $(p) for rows $(start_row):$(end_row)")
            
            # Send dimensions
            dims = [N, rows_per_proc]
            MPI.Send(dims, comm; dest=p, tag=0)
            
            # Send A rows and B
            A_rows = A[start_row:end_row, :]
            log_message(comm, "Sending $(size(A_rows,1))×$(size(A_rows,2)) slice of A to rank $(p)")
            MPI.Send(A_rows, comm; dest=p, tag=1)
            
            log_message(comm, "Sending full matrix B to rank $(p)")
            MPI.Send(B, comm; dest=p, tag=2)
        end
        
        send_time = MPI.Wtime() - send_start
        log_message(comm, "Finished sending data to all workers in $(send_time) seconds")
        
        # Receive results
        receive_start = MPI.Wtime()
        
        for p in 1:(nprocs-1)
            start_row = p * rows_per_proc + 1
            end_row = (p + 1) * rows_per_proc
            
            log_message(comm, "Waiting for results from rank $(p) for rows $(start_row):$(end_row)")
            
            # Prepare buffer for results
            C_part = zeros(eltype(C), rows_per_proc, N)
            
            # Receive computed chunk
            status = MPI.Recv!(C_part, comm, MPI.Status; source=p, tag=3)
            
            log_message(comm, "Received results from rank $(p)")
            
            # Copy to C
            C[start_row:end_row, :] = C_part
            
            # Visualize small portions of result matrix
            if N <= 20
                log_message(comm, "Result matrix part from rank $(p):\n$(matrix_to_string(C_part))")
            end
        end
        
        receive_time = MPI.Wtime() - receive_start
        log_message(comm, "Finished receiving results in $(receive_time) seconds")
        
        # Visualize small portions of final result matrix
        if N <= 20
            log_message(comm, "Final result matrix C:\n$(matrix_to_string(C))")
        else
            log_message(comm, "Final result matrix C preview:\n$(matrix_to_string(C))")
        end
        
    else  # Worker processes
        # Receive dimensions
        dims_buf = zeros(Int, 2)
        MPI.Recv!(dims_buf, comm, MPI.Status; source=0, tag=0)
        N, rows_per_proc = dims_buf
        
        log_message(comm, "Received dimensions: N=$(N), rows_per_proc=$(rows_per_proc)")
        
        # Prepare buffers
        A_rows = zeros(Float64, rows_per_proc, N)
        B_mat = zeros(Float64, N, N)
        
        # Receive A rows
        start_recv_a = MPI.Wtime()
        MPI.Recv!(A_rows, comm, MPI.Status; source=0, tag=1)
        recv_a_time = MPI.Wtime() - start_recv_a
        
        log_message(comm, "Received A rows ($(size(A_rows,1))×$(size(A_rows,2))) in $(recv_a_time) seconds")
        if N <= 20
            log_message(comm, "My portion of A:\n$(matrix_to_string(A_rows))")
        else
            log_message(comm, "My portion of A preview:\n$(matrix_to_string(A_rows))")
        end
        
        # Receive B matrix
        start_recv_b = MPI.Wtime()
        MPI.Recv!(B_mat, comm, MPI.Status; source=0, tag=2)
        recv_b_time = MPI.Wtime() - start_recv_b
        
        log_message(comm, "Received B matrix ($(size(B_mat,1))×$(size(B_mat,2))) in $(recv_b_time) seconds")
        if N <= 20
            log_message(comm, "Matrix B:\n$(matrix_to_string(B_mat))")
        end
        
        # Compute result
        compute_start = MPI.Wtime()
        log_message(comm, "Computing my portion of C...")
        
        C_part = zeros(Float64, rows_per_proc, N)
        for i in 1:rows_per_proc
            for j in 1:N
                C_part[i, j] = 0
                for k in 1:N
                    C_part[i, j] += A_rows[i, k] * B_mat[k, j]
                end
            end
        end
        
        compute_time = MPI.Wtime() - compute_start
        log_message(comm, "Computation completed in $(compute_time) seconds")
        
        # Send result back to rank 0
        send_start = MPI.Wtime()
        if N <= 20
            log_message(comm, "Sending result matrix:\n$(matrix_to_string(C_part))")
        else
            log_message(comm, "Sending result matrix preview:\n$(matrix_to_string(C_part))")
        end
        
        MPI.Send(C_part, comm; dest=0, tag=3)
        send_time = MPI.Wtime() - send_start
        log_message(comm, "Sent results to rank 0 in $(send_time) seconds")
    end
    
    # Calculate total execution time
    total_time = MPI.Wtime() - start_time
    log_message(comm, "Total execution time: $(total_time) seconds")
    
    # Only continue to verify on rank 0
    return C
end

function testit(load)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    nprocs = MPI.Comm_size(comm)
    
    # Synchronize before starting
    MPI.Barrier(comm)
    
    if rank == 0
        println("\n==========================================")
        println("Starting matrix multiplication test")
        println("Number of processes: $(nprocs)")
        println("Load per process: $(load)")
        N = load*nprocs
        println("Total matrix size: $(N)×$(N)")
        println("==========================================\n")
    else
        N = 0
    end
    
    # Start timing
    start_time = MPI.Wtime()
    
    # Initialize matrices on rank 0
    if rank == 0
        A = rand(N, N)
        B = rand(N, N)
        C = zeros(N, N)
        
        # For small matrices, print them
        if N <= 10
            println("Matrix A:")
            display(A)
            println("\nMatrix B:")
            display(B)
            println()
        end
    else
        A = Matrix{Float64}(undef, 0, 0)
        B = Matrix{Float64}(undef, 0, 0)
        C = Matrix{Float64}(undef, 0, 0)
    end
    
    # Run the matrix multiplication
    matmul_mpi_3!(C, A, B)
    
    # Calculate overall performance metrics
    end_time = MPI.Wtime()
    elapsed = end_time - start_time
    
    if rank == 0
        # Verify result
        D = A * B  # Built-in multiplication for verification
        is_correct = isapprox(C, D, atol=1e-10)
        
        # Calculate FLOPS (floating point operations)
        flops = 2.0 * N^3  # Each multiply-add is 2 operations
        gflops = flops / (elapsed * 1e9)
        
        println("\n==========================================")
        println("Performance Results:")
        println("------------------------------------------")
        println("Matrix size: $(N)×$(N)")
        println("Number of processes: $(nprocs)")
        println("Total execution time: $(elapsed) seconds")
        println("Performance: $(gflops) GFLOPS")
        println("Test result: $(is_correct ? "PASSED 🥳" : "FAILED 😢")")
        println("==========================================")
    end
    
    # Collect timing statistics from all processes
    if rank == 0
        println("\nTiming statistics across all processes:")
    end
    
    # Let each process report its time
    for p in 0:nprocs-1
        MPI.Barrier(comm)
        if rank == p
            local_time = elapsed
            println("Rank $(rank): $(local_time) seconds")
        end
    end
    
    # Final barrier to ensure clean output
    MPI.Barrier(comm)
    
    if rank == 0
        println("\nMatrix multiplication test completed!")
    end
end

# Run with different load sizes
testit(10)  # Small matrices to show the flow clearly
MPI.Barrier(MPI.COMM_WORLD)
testit(100) # Larger matrices for performance measurement