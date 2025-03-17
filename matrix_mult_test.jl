using Test, BenchmarkTools, Distributed

# Ensure we have workers
if nworkers() < 2
    addprocs(4)  # Add workers if none exist
end

@everywhere function matmul_seq!(C, A, B)
    m = size(C, 1)
    n = size(C, 2)
    l = size(A, 2)
    @assert size(A, 1) == m
    @assert size(B, 2) == n
    @assert size(B, 1) == l
    z = zero(eltype(C))
    for j in 1:n
        for i in 1:m
            Cij = z
            for k in 1:l
                @inbounds Cij += A[i, k] * B[k, j]
            end
            C[i, j] = Cij
        end
    end
    C
end

# Include our implementation
include("matrix_parallel_mult.jl")

# Test correct functionality
println("\n=== Testing correctness ===\n")
P = nworkers()
load = 10  # Small for testing
N = load * P
A = rand(N, N)
B = rand(N, N)
C = similar(A)

# Test sequential
C_seq = copy(C)
matmul_seq!(C_seq, A, B)
@test C_seq ≈ A*B

# Test our parallel implementation
C_par = copy(C)
matmul_dist_3!(C_par, A, B)
@test C_par ≈ A*B

# Compare sequential and parallel results
@test C_seq ≈ C_par

# Performance test with a reasonable load
println("\n=== Testing performance ===\n")
load = 50
N = load * P
A = rand(N, N)
B = rand(N, N)
C = similar(A)

results = measure_performance(matmul_dist_3!, C, A, B, trials=3)