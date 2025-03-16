# Save this as cleanup.jl
using Distributed

# Remove any existing workers
if nprocs() > 1
    @info "Removing $(nprocs()-1) worker processes..."
    rmprocs(workers())
end

# Force garbage collection
GC.gc(true)

# Print memory usage
@info "Current memory usage: $(round(Sys.total_memory() - Sys.free_memory(), digits=2) / 1e6) MB"