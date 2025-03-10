function cache_friendly_matmul(A, B, C, blocksize=64)
    m, n = size(A)
    n, p = size(B)
    
    # Zero out the result matrix
    fill!(C, 0.0)
    
    # Loop over blocks
    for kk = 1:blocksize:n
        for jj = 1:blocksize:p
            for ii = 1:blocksize:m
                # Process block
                for k = kk:min(kk+blocksize-1, n)
                    for j = jj:min(jj+blocksize-1, p)
                        # Load column of B into cache
                        Bj = B[k, j]
                        for i = ii:min(ii+blocksize-1, m)
                            C[i, j] += A[i, k] * Bj
                        }
                    end
                end
            end
        end
    end
    return C
end

# This algorithm implements a blocked matrix multiplication that is optimized for CPU cache hierarchy. 
# By processing the matrices in small blocks that fit in the L1/L2 cache, 
#     it significantly reduces cache misses and improves performance compared to naive implementations.
