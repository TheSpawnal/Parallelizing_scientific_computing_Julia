function parallel_quicksort(arr)
    if length(arr) <= 1
        return arr
    end
    
    pivot = arr[rand(1:end)]
    left = filter(x -> x < pivot, arr)
    right = filter(x -> x > pivot, arr)
    equal = filter(x -> x == pivot, arr)
    # For larger arrays, process partitions in parallel
    if length(arr) > 10_000
        t1 = @spawn parallel_quicksort(left)
        t2 = @spawn parallel_quicksort(right)
        return vcat(fetch(t1), equal, fetch(t2))
    else
        # Process smaller arrays sequentially to avoid task creation overhead
        return vcat(parallel_quicksort(left), equal, parallel_quicksort(right))
    end
end

# Usage
data = rand(1:1000, 1_000_000)
sorted = parallel_quicksort(data)

# This algorithm demonstrates Julia's task-based parallelism using the work-stealing scheduler. 
# The @spawn macro creates lightweight tasks that are automatically distributed across available threads. 
# The recursive nature of quicksort naturally creates a task tree that efficiently utilizes multiple cores 
# while the threshold prevents excessive task creation overhead.
# Each of these algorithms showcases different aspects of Julia's parallel computing capabilities, 
#     from low-level cache optimization to high-level distributed computing patterns.
