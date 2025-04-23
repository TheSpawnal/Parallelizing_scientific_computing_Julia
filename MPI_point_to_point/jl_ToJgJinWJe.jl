using MPI
MPI.Init()
comm = MPI.COMM_WORLD
nranks = MPI.Comm_size(comm)
rank = MPI.Comm_rank(comm)
host = MPI.Get_processor_name()
println("Hello from $host, I am process $rank of $nranks processes!")
MPI.Finalize()
