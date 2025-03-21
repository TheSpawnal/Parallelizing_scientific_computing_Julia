"""
Implementation of the producer-consumer pattern using Julia's tasks and channels.
This example simulates a system with multiple producers creating work items
and multiple consumers processing them, with rate limiting.

It implements the classic producer_consumer pattern with multiple producers creating work
items at different rates and multiple consumers processing them. 
It demonstrates rate limiting, work distribution, and efficient resource utilization.
The code shows how channels can be used to decouple producers and consumers, allowing them to operate at different speeds while maintaining a balanced workflow.
"""

using Printf
using Dates

# Define colorful output function
function print_with_color(message, color)
    colors = Dict(
        "black" => "\e[30m",
        "red" => "\e[31m",
        "green" => "\e[32m",
        "yellow" => "\e[33m",
        "blue" => "\e[34m",
        "magenta" => "\e[35m",
        "cyan" => "\e[36m",
        "white" => "\e[37m",
        "reset" => "\e[0m"
    )
    
    timestamp = Dates.format(now(), "HH:MM:SS.sss")
    println(colors[color], "[$timestamp] ", message, colors["reset"])
end

# Work item structure
struct WorkItem
    id::Int
    producer_id::Int
    complexity::Float64  # 0.0 to 1.0, affects processing time
    data::Dict{String, Any}
    created_at::DateTime
end

# Producer function - creates work items at a specified rate
function producer(id::Int, work_channel::Channel, count::Int, rate_per_second::Float64)
    print_with_color("Producer $id started. Will produce $count items at rate of $rate_per_second/sec", "blue")
    
    delay_between_items = 1.0 / rate_per_second
    
    for i in 1:count
        # Create a work item with random complexity
        complexity = rand() * 0.8 + 0.2  # Between 0.2 and 1.0
        
        item = WorkItem(
            i,
            id,
            complexity,
            Dict("value" => rand(1:100), "text" => "Item $(i) from producer $(id)"),
            now()
        )
        
        # Put the item in the channel
        put!(work_channel, item)
        print_with_color("Producer $id: Created item $(item.id) with complexity $(round(item.complexity, digits=2))", "cyan")
        
        # Rate limiting
        sleep(delay_between_items)
        yield()  # Allow other tasks to run
    end
    
    print_with_color("Producer $id: Finished producing $count items", "blue")
end

# Consumer function - processes work items
function consumer(id::Int, work_channel::Channel, results_channel::Channel)
    print_with_color("Consumer $id started", "green")
    
    item_count = 0
    total_processing_time = 0.0
    
    while isopen(work_channel)
        try
            # Try to get a work item
            item = take!(work_channel)
            
            # Process the item (simulated by sleeping based on complexity)
            process_time = item.complexity * (1.0 + rand() * 0.5)  # Add some randomness
            
            print_with_color("Consumer $id: Processing item $(item.id) from producer $(item.producer_id) (complexity: $(round(item.complexity, digits=2)))", "yellow")
            
            # Simulate processing in chunks to allow yielding
            chunks = 5
            chunk_time = process_time / chunks
            
            for _ in 1:chunks
                sleep(chunk_time)
                yield()  # Allow other tasks to run
            end
            
            # Calculate actual processing time and latency
            processing_time = process_time
            latency = (now() - item.created_at).value / 1000.0  # in milliseconds
            
            # Create a result
            result = Dict(
                "item_id" => item.id,
                "producer_id" => item.producer_id,
                "consumer_id" => id,
                "complexity" => item.complexity,
                "processing_time" => processing_time,
                "latency" => latency,
                "output" => item.data["value"] * 2  # Some transformation
            )
            
            # Send the result
            put!(results_channel, result)
            
            print_with_color("Consumer $id: Completed item $(item.id) in $(round(processing_time, digits=2))s (latency: $(round(latency, digits=1))ms)", "green")
            
            # Update statistics
            item_count += 1
            total_processing_time += processing_time
            
        catch e
            if isa(e, InvalidStateException) && e.state == :closed
                # Channel closed, which is normal
                break
            else
                # Unexpected error
                print_with_color("Consumer $id: Error: $e", "red")
            end
        end
    end
    
    avg_time = item_count > 0 ? total_processing_time / item_count : 0
    print_with_color("Consumer $id: Shutting down after processing $item_count items (avg time: $(round(avg_time, digits=2))s)", "green")
end

# Result collector function
function result_collector(results_channel::Channel)
    print_with_color("Result collector started", "magenta")
    
    results = []
    
    while isopen(results_channel)
        try
            result = take!(results_channel)
            push!(results, result)
            
            # Print every 5th result
            if length(results) % 5 == 0
                print_with_color("Collector: Received $(length(results)) results so far", "magenta")
            end
            
        catch e
            if isa(e, InvalidStateException) && e.state == :closed
                # Channel closed, which is normal
                break
            else
                # Unexpected error
                print_with_color("Collector: Error: $e", "red")
            end
        end
    end
    
    # Calculate and display statistics
    if !isempty(results)
        total_items = length(results)
        avg_latency = sum(r -> r["latency"], results) / total_items
        avg_processing = sum(r -> r["processing_time"], results) / total_items
        max_latency = maximum(r -> r["latency"], results)
        
        # Group by producer
        by_producer = Dict()
        for r in results
            producer = r["producer_id"]
            if !haskey(by_producer, producer)
                by_producer[producer] = []
            end
            push!(by_producer[producer], r)
        end
        
        # Group by consumer
        by_consumer = Dict()
        for r in results
            consumer = r["consumer_id"]
            if !haskey(by_consumer, consumer)
                by_consumer[consumer] = []
            end
            push!(by_consumer[consumer], r)
        end
        
        print_with_color("📊 Results Summary:", "magenta")
        print_with_color(@sprintf("   - Total items processed: %d", total_items), "magenta")
        print_with_color(@sprintf("   - Average latency: %.2f ms", avg_latency), "magenta")
        print_with_color(@sprintf("   - Average processing time: %.2f s", avg_processing), "magenta")
        print_with_color(@sprintf("   - Maximum latency: %.2f ms", max_latency), "magenta")
        
        print_with_color("   - Items per producer:", "magenta")
        for (producer, items) in sort(collect(by_producer), by=first)
            print_with_color(@sprintf("      - Producer %d: %d items", producer, length(items)), "magenta")
        end
        
        print_with_color("   - Items per consumer:", "magenta")
        for (consumer, items) in sort(collect(by_consumer), by=first)
            print_with_color(@sprintf("      - Consumer %d: %d items (avg: %.2f s)", 
                consumer, length(items), sum(i -> i["processing_time"], items) / length(items)), "magenta")
        end
    end
    
    print_with_color("Result collector: Finished collecting all results", "magenta")
end

# Run the producer-consumer system
function run_producer_consumer_system(
    num_producers::Int = 3, 
    num_consumers::Int = 2, 
    items_per_producer::Int = 10, 
    production_rate::Float64 = 2.0,  # items per second
    buffer_size::Int = 20
)
    print_with_color("🚀 Starting producer-consumer system with:", "white")
    print_with_color("   - $num_producers producers ($items_per_producer items each at $production_rate/sec)", "white")
    print_with_color("   - $num_consumers consumers", "white")
    print_with_color("   - Buffer size: $buffer_size", "white")
    
    # Create channels
    work_channel = Channel{WorkItem}(buffer_size)
    results_channel = Channel{Dict}(buffer_size)
    
    # Run the system
    @sync begin
        # Start the collectors first (they need to be ready to receive)
        @async result_collector(results_channel)
        
        # Start consumers
        for i in 1:num_consumers
            @async consumer(i, work_channel, results_channel)
        end
        
        # Start producers
        for i in 1:num_producers
            @async producer(i, work_channel, items_per_producer, production_rate)
        end
        
        # When all producers finish, close the work channel
        @async begin
            # Wait for all producers to finish
            sleep((items_per_producer / production_rate) * 1.2)  # Add 20% buffer
            close(work_channel)
            print_with_color("All producers have finished, work channel closed", "white")
            
            # Wait for all consumers to finish processing remaining items
            sleep(5.0)  # Give them time to finish
            close(results_channel)
            print_with_color("All consumers have finished, results channel closed", "white")
        end
    end
    
    print_with_color("🏁 Producer-consumer system completed", "white")
end

# Run the example with configured parameters
println("Starting producer-consumer pattern demonstration...")
run_producer_consumer_system(3, 2, 10, 1.5, 15)
