# Exercise 1

# Implement the parallel matrix-matrix multiplication (Algorithm 3) using MPI collectives instead 
# of point-to-point communication. I.e., this is the same exercise as in previous notebook, 
# but using different functions for communication.

function matmul_mpi_3!(C,A,B)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    P = MPI.Comm_size(comm)
    root = 0
    if  rank == root
        N = size(A,1)
        Nref = Ref(N)
    else
        Nref = Ref(0)
    end
    MPI.Bcast!(Nref,comm;root)
    N = Nref[]
    if  rank == root
        myB = B
    else
        myB = zeros(N,N)
    end
    MPI.Bcast!(myB,comm;root)
    L = div(N,P)
    # Tricky part
    # Julia works "col major"
    myAt = zeros(N,L)
    At = collect(transpose(A))
    MPI.Scatter!(At,myAt,comm;root)
    myCt = transpose(myB)*myAt
    Ct = similar(C)
    MPI.Gather!(myCt,Ct,comm;root)
    C .= transpose(Ct)
    C
end
# This other solution uses a column partition instead
# of a row partition. It is more natural to work with column
# partitions in Julia if possible since matrices are in "col major"
# format. Note that we do not need all the auxiliary transposes anymore.

function matmul_mpi_3!(C,A,B)
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    P = MPI.Comm_size(comm)
    root = 0
    if  rank == root
        N = size(A,1)
        Nref = Ref(N)
    else
        Nref = Ref(0)
    end
    MPI.Bcast!(Nref,comm;root)
    N = Nref[]
    if  rank == root
        myA = A
    else
        myA = zeros(N,N)
    end
    MPI.Bcast!(myA,comm;root)
    L = div(N,P)
    myB = zeros(N,L)
    MPI.Scatter!(B,myB,comm;root)
    myC = myA*myB
    MPI.Gather!(myC,C,comm;root)
    C
end