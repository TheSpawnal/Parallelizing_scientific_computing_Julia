# ex1.jl
using MPI
MPI.Init()

function matmul_mpi_3!(C, A, B)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    nprocs = MPI.Comm_size(comm)
    
    if rank == 0
        # Only rank 0 has the actual matrices
        N = size(A, 1)
        @assert N % nprocs == 0  # Ensure N is divisible by nprocs
        rows_per_proc = div(N, nprocs)
        
        # Process own chunk (first rows_per_proc rows)
        for i in 1:rows_per_proc
            for j in 1:N
                C[i, j] = 0
                for k in 1:N
                    C[i, j] += A[i, k] * B[k, j]
                end
            end
        end
        
        # Send data to other processes
        for p in 1:(nprocs-1)
            start_row = p * rows_per_proc + 1
            end_row = (p + 1) * rows_per_proc
            
            # Send dimensions
            dims = [N, rows_per_proc]
            MPI.Send(dims, comm; dest=p, tag=0)
            
            # Send A rows and B
            A_rows = A[start_row:end_row, :]
            MPI.Send(A_rows, comm; dest=p, tag=1)
            MPI.Send(B, comm; dest=p, tag=2)
        end
        
        # Receive results
        for p in 1:(nprocs-1)
            start_row = p * rows_per_proc + 1
            end_row = (p + 1) * rows_per_proc
            
            # Prepare buffer for results
            C_part = zeros(eltype(C), rows_per_proc, N)
            
            # Receive computed chunk
            MPI.Recv!(C_part, comm, MPI.Status; source=p, tag=3)
            
            # Copy to C
            C[start_row:end_row, :] = C_part
        end
    else
        # Receive dimensions
        dims_buf = zeros(Int, 2)
        MPI.Recv!(dims_buf, comm, MPI.Status; source=0, tag=0)
        N, rows_per_proc = dims_buf
        
        # Prepare buffers
        A_rows = zeros(Float64, rows_per_proc, N)
        B_mat = zeros(Float64, N, N)
        
        # Receive A rows
        MPI.Recv!(A_rows, comm, MPI.Status; source=0, tag=1)
        
        # Receive B matrix
        MPI.Recv!(B_mat, comm, MPI.Status; source=0, tag=2)
        
        # Compute result
        C_part = zeros(Float64, rows_per_proc, N)
        for i in 1:rows_per_proc
            for j in 1:N
                C_part[i, j] = 0
                for k in 1:N
                    C_part[i, j] += A_rows[i, k] * B_mat[k, j]
                end
            end
        end
        
        # Send result back to rank 0
        MPI.Send(C_part, comm; dest=0, tag=3)
    end
    
    return C
end

function testit(load)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    if rank == 0
        P = MPI.Comm_size(comm)
        N = load*P
    else
        N = 0
    end
    A = rand(N,N)
    B = rand(N,N)
    C = similar(A)
    matmul_mpi_3!(C,A,B)
    if rank == 0
        if !(C ≈ A*B)
            println("Test failed 😢")
        else
            println("Test passed 🥳")
        end
    end
end

testit(100)