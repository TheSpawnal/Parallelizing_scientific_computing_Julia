# Implement the parallel matrix-matrix multiplication (Algorithm 3) in previous notebook 
# using MPI instead of Distributed. Use this function signature:

# function matmul_mpi_3!(C,A,B)

# Assume that the input matrices A and B are given only on rank 0, 
# the other ranks get dummy empty matrices to save memory. 
# You need to communicate the required parts to other ranks. 
# For simplicity you can assume that A and B are square matrices and 
# that the number of rows is a multiple of the number of processes 
# (on rank 0). The result C should be overwritten only on rank 0. 
# You can use the following cell to implement and check your result. 


function matmul_mpi_3!(C,A,B)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    P = MPI.Comm_size(comm)
    if  rank == 0
        N = size(A,1)
        myB = B
        for dest in 1:(P-1)
            MPI.Send(B,comm;dest)
        end
    else
        source = 0
        status = MPI.Probe(comm,MPI.Status;source)
        count = MPI.Get_count(status,eltype(B))
        N = Int(sqrt(count))
        myB = zeros(N,N)
        MPI.Recv!(myB,comm;source)
    end
    L = div(N,P)
    myA = zeros(L,N)
    if  rank == 0
        lb = L*rank+1
        ub = L*(rank+1)
        myA[:,:] = view(A,lb:ub,:)
        for dest in 1:(P-1)
            lb = L*dest+1
            ub = L*(dest+1)
            MPI.Send(view(A,lb:ub,:),comm;dest)
        end
    else
        source = 0
        MPI.Recv!(myA,comm;source)
    end
    myC = myA*myB
    if rank == 0
        lb = L*rank+1
        ub = L*(rank+1)
        C[lb:ub,:] = myC
        for source in 1:(P-1)
            lb = L*source+1
            ub = L*(source+1)
            MPI.Recv!(view(C,lb:ub,:),comm;source)
        end
    else
        dest = 0
        MPI.Send(myC,comm;dest)
    end
    C
end