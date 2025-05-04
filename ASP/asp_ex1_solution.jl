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