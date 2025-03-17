using Test, BenchmarkTools, Distributed

# Ensure we have workers
if nworkers() < 2
    addprocs(4)  # Add workers if none exist
end

# Include our implementation
include("parallel-matmul.jl")

# Test correct functionality
@testset "Matrix Multiplication Correctness" begin
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
end

# Performance tests with different loads
@testset "Performance with varying loads" begin
    P = nworkers()
    
    # Test with different loads
    for load in [50, 100, 200]
        N = load * P
        println("\n\n")
        println("="^80)
        println("TESTING WITH MATRIX SIZE $(N)×$(N) (LOAD FACTOR: $load)")
        println("="^80)
        
        A = rand(N, N)
        B = rand(N, N)
        C = similar(A)
        
        # Measure performance
        results = measure_performance(matmul_dist_3!, C, A, B, trials=3)
        
        # Validate acceptable performance
        # For higher loads, we expect better efficiency
        if load >= 100
            @test results["efficiency"] > 50.0  # At least 50% efficiency for decent loads
        end
    end
end
