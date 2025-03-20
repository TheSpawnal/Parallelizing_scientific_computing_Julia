# fixed_mpi_matmul.jl
using MPI
using Printf

MPI.Init()

function log_message(comm, message)
    rank = MPI.Comm_rank(comm)
    println("RANK $(rank): $(message)")
end

function matmul_mpi_collective!(C, A, B)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    nprocs = MPI.Comm_size(comm)
    
    # Start timing
    start_time = MPI.Wtime()
    log_message(comm, "Starting matrix multiplication")
    
    if rank == 0
        N = size(A, 1)
        log_message(comm, "Matrix dimensions: $(N)×$(N)")
        
        # Make sure matrix size is divisible by number of processes
        @assert N % nprocs == 0 "Matrix size must be divisible by number of processes"
        rows_per_proc = div(N, nprocs)
        log_message(comm, "Each process will handle $(rows_per_proc) rows")
    else
        N = 0
        rows_per_proc = 0
    end
    
    # Broadcast dimensions to all processes
    dims = zeros(Int, 2)
    if rank == 0
        dims = [size(A, 1), div(size(A, 1), nprocs)]
    end
    
    MPI.Bcast!(dims, 0, comm)
    
    if rank != 0
        N = dims[1]
        rows_per_proc = dims[2]
        log_message(comm, "Received dimensions: N=$(N), rows_per_proc=$(rows_per_proc)")
    end
    
    # Broadcast matrix B to all processes
    if rank != 0
        B = zeros(Float64, N, N)
    end
    
    MPI.Bcast!(B, 0, comm)
    log_message(comm, "Received matrix B")
    
    # Scatter rows of A to each process using regular point-to-point communication
    # (since Scatterv! seems to have API issues)
    A_local = zeros(Float64, rows_per_proc, N)
    
    if rank == 0
        # Process own chunk (first rows_per_proc rows)
        for i in 1:rows_per_proc
            for j in 1:N
                A_local[i,j] = A[i,j]
            end
        end
        
        # Send chunks to other processes
        for p in 1:(nprocs-1)
            start_row = p * rows_per_proc + 1
            end_row = (p + 1) * rows_per_proc
            
            # Send A rows
            A_rows = A[start_row:end_row, :]
            MPI.Send(A_rows, comm; dest=p, tag=1)
        end
        
        log_message(comm, "Sent A chunks to all processes")
    else
        # Receive my chunk of A
        MPI.Recv!(A_local, comm, MPI.Status; source=0, tag=1)
    end
    
    log_message(comm, "Received A rows")
    
    # Compute local result
    log_message(comm, "Computing my portion of C...")
    
    C_local = zeros(Float64, rows_per_proc, N)
    for i in 1:rows_per_proc
        for j in 1:N
            C_local[i, j] = 0.0
            for k in 1:N
                C_local[i, j] += A_local[i, k] * B[k, j]
            end
        end
    end
    
    log_message(comm, "Computation completed")
    
    # Gather results back to rank 0 using point-to-point communication
    if rank == 0
        # Copy my local result to C
        for i in 1:rows_per_proc
            for j in 1:N
                C[i, j] = C_local[i, j]
            end
        end
        
        # Receive results from other processes
        for p in 1:(nprocs-1)
            start_row = p * rows_per_proc + 1
            end_row = (p + 1) * rows_per_proc
            
            # Prepare buffer for results
            C_part = zeros(Float64, rows_per_proc, N)
            
            # Receive computed chunk
            MPI.Recv!(C_part, comm, MPI.Status; source=p, tag=3)
            
            # Copy to C
            for i in 1:rows_per_proc
                for j in 1:N
                    C[start_row+i-1, j] = C_part[i, j]
                end
            end
        end
        
        log_message(comm, "Gathered all results")
    else
        # Send my results to rank 0
        MPI.Send(C_local, comm; dest=0, tag=3)
    end
    
    log_message(comm, "Finished matrix multiplication")
    
    return C
end

function testit(load)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    nprocs = MPI.Comm_size(comm)
    
    # Synchronize before starting
    MPI.Barrier(comm)
    
    if rank == 0
        println("\n=== MATRIX MULTIPLICATION TEST ===")
        println("Number of processes: $(nprocs)")
        println("Load per process: $(load)")
        N = load * nprocs
        println("Total matrix size: $(N)×$(N)")
        println("===================================\n")
    else
        N = 0
    end
    
    # Broadcast N to all processes
    N_buf = [0]
    if rank == 0
        N_buf[1] = load * nprocs
    end
    MPI.Bcast!(N_buf, 0, comm)
    N = N_buf[1]
    
    # Initialize matrices on rank 0
    if rank == 0
        A = rand(N, N)
        B = rand(N, N)
        C = zeros(N, N)
    else
        A = Matrix{Float64}(undef, 0, 0)
        B = Matrix{Float64}(undef, 0, 0)
        C = Matrix{Float64}(undef, 0, 0)
    end
    
    # Run the matrix multiplication
    matmul_mpi_collective!(C, A, B)
    
    # Verify result on rank 0
    if rank == 0
        # Calculate reference result
        D = A * B  # Built-in multiplication for verification
        
        # Verify
        is_correct = isapprox(C, D, atol=1e-10)
        
        println("\n=== RESULTS ===")
        println("Test result: $(is_correct ? "PASSED ✓" : "FAILED ✗")")
        println("==============\n")
    end
    
    # Final barrier for clean output
    MPI.Barrier(comm)
end

# Run with a small test case
testit(3)

MPI.Finalize()

