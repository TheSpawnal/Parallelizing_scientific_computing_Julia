#Exercise 1
# Modify the `floyd_iterations!` function so that it is 
# guaranteed that the result is computed correctly. 
# Use `MPI.Bcast!` to solve the synchronization problem. 
# Note: only use `MPI.Bcast!`in `floyd_iterations!`, 
# do not use other MPI directives. 
# You can assume that the number of rows is a multiple of the number of processes.

#(claude 3.7)
function floyd_iterations!(myC, comm)
    L = size(myC, 1)
    N = size(myC, 2)
    rank = MPI.Comm_rank(comm)
    P = MPI.Comm_size(comm)
    lb = L * rank + 1
    ub = L * (rank + 1)
    
    # Buffer to store the row k
    C_k = similar(myC, N)
    
    for k in 1:N
        # Determine which rank owns row k
        owner_rank = div(k - 1, L)
        
        if rank == owner_rank
            # If I'm the owner of row k, copy it to C_k
            local_row_index = k - lb + 1
            C_k[:] = view(myC, local_row_index, :)
        end
        
        # Broadcast row k from its owner to all processes
        MPI.Bcast!(C_k, owner_rank, comm)
        
        # Now all processes have row k, perform the Floyd update
        for j in 1:N
            for i in 1:L
                myC[i, j] = min(myC[i, j], myC[i, k] + C_k[j])
            end
        end
    end
    
    myC
end

#offical solution: 
function floyd_iterations!(myC,comm)
    L = size(myC,1)
    N = size(myC,2)
    rank = MPI.Comm_rank(comm)
    P = MPI.Comm_size(comm)
    lb = L*rank+1
    ub = L*(rank+1)
    C_k = similar(myC,N)
    for k in 1:N
        if (lb<=k) && (k<=ub)
            # If I have the row, fill in the buffer
            myk = (k-lb)+1
            C_k[:] = view(myC,myk,:)
        end
        # We need to find out the owner of row k.
        # Easy since N is a multiple of P
        root = div(k-1,L)
        MPI.Bcast!(C_k,comm;root)
        # Now, we have the data dependencies and
        # we can do the updates locally
        for j in 1:N
            for i in 1:L
                myC[i,j] = min(myC[i,j],myC[i,k]+C_k[j])
            end
        end
    end
    myC
end