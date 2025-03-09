using MPI
#message passing inteface
MPI.Init()
comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)
nranks = MPI.Comm_size(comm)
println("Hello hell, I am rank $rank of $nranks")

#follow MPI impl/notion
