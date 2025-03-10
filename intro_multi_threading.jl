function parallel_sum(arr)
    n = length(arr)
    result = zeros(Threads.nthreads())
    
    Threads.@threads for i in 1:n
        tid = Threads.threadid()
        result[tid] += arr[i]
    end
    
    return sum(result)
end

# Usage
data = rand(10_000_000)
@time parallel_sum(data)
