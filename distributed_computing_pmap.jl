using Distributed
addprocs(4)  # Add 4 worker processes

@everywhere function heavy_computation(x)
    # Simulate complex work
    sleep(1)
    return x^2
end

function distributed_process(data)
    return pmap(heavy_computation, data)
end

# Usage
result = distributed_process(1:10)

# This algorithm leverages Julia's distributed computing capabilities to process data across multiple CPU cores 
# or even machines. The @everywhere macro ensures the function is defined on all worker processes, 
#     and pmap automatically handles work distribution and result collection.
