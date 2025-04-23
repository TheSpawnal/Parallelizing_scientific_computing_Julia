### Exercise 2

# telephone game algorithm.

# Rank 0 generates a message (an integer). 
# Rank 0 sends the message to rank 1. 
# Rank 1 receives the message, increments the message by 1, and sends the result to rank 2. 
# Rank 2 receives the message, increments the message by 1, and sends the result to rank 3. 
# Etc. The last rank sends back the message to rank 0 closing the ring. 
# See the next figure. Implement the communications using MPI. 
# Do not use `Distributed`. 

using MPI
MPI.Init()
comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)
nranks = MPI.Comm_size(comm)
buffer = Ref(0)
if rank == 0
    msg = 2
    buffer[] = msg
    println("msg = $(buffer[])")
    MPI.Send(buffer,comm;dest=rank+1,tag=0)
    MPI.Recv!(buffer,comm;source=nranks-1,tag=0)
    println("msg = $(buffer[])")
else
    dest = if (rank != nranks-1)
        rank+1
    else
        0
    end
    MPI.Recv!(buffer,comm;source=rank-1,tag=0)
    buffer[] += 1
    println("msg = $(buffer[])")
    MPI.Send(buffer,comm;dest,tag=0)
end
