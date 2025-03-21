using Printf

"""
A demonstration of a data processing pipeline using channels and tasks.
Each stage of the pipeline processes data and passes it to the next stage.
This example demonstrates a multi-stage data pipeline using channels to pass data between stages. 
Each stage (generator, transformer, analyzer, collector) runs as a separate task, processing data asynchronously and cooperatively yielding control to maintain system responsiveness.
The code showcases buffered channels for communication between pipeline stages and the @sync/@async macros for task synchronization.
"""

# Define colorful output function
function print_color(color, message)
    colors = Dict(
        "red" => "\e[31m",
        "green" => "\e[32m",
        "yellow" => "\e[33m",
        "blue" => "\e[34m",
        "magenta" => "\e[35m",
        "cyan" => "\e[36m",
        "reset" => "\e[0m"
    )
    
    print(colors[color], message, colors["reset"])
end

function data_generator(out_channel::Channel, count::Int)
    print_color("cyan", "🔄 Generator: Starting to produce data\n")
    
    for i in 1:count
        data = Dict("id" => i, "value" => rand(1:100))
        put!(out_channel, data)
        print_color("cyan", "🔄 Generator: Produced item $i: $(data["value"])\n")
        sleep(0.2)  # Simulate some work
    end
    
    print_color("cyan", "🔄 Generator: Finished producing data\n")
    close(out_channel)
end

function data_transformer(in_channel::Channel, out_channel::Channel)
    print_color("green", "🔧 Transformer: Starting to process data\n")
    
    for data in in_channel
        # Transform the data (multiply by 2)
        data["value"] *= 2
        print_color("green", "🔧 Transformer: Processed item $(data["id"]): $(data["value"])\n")
        put!(out_channel, data)
        yield()  # Cooperative multitasking
    end
    
    print_color("green", "🔧 Transformer: Finished processing data\n")
    close(out_channel)
end

function data_analyzer(in_channel::Channel, results_channel::Channel)
    print_color("yellow", "📊 Analyzer: Starting to analyze data\n")
    total = 0
    count = 0
    
    for data in in_channel
        # Analyze the data (checking if it's divisible by 3)
        is_divisible = data["value"] % 3 == 0
        analysis = Dict(
            "id" => data["id"],
            "value" => data["value"],
            "divisible_by_3" => is_divisible
        )
        
        total += data["value"]
        count += 1
        
        print_color("yellow", "📊 Analyzer: Analyzed item $(data["id"]): $(is_divisible ? "divisible" : "not divisible") by 3\n")
        put!(results_channel, analysis)
        yield()  # Cooperative multitasking
    end
    
    # Add summary statistics
    if count > 0
        put!(results_channel, Dict("summary" => true, "average" => total / count))
    end
    
    print_color("yellow", "📊 Analyzer: Finished analysis\n")
    close(results_channel)
end

function collector(results_channel::Channel)
    print_color("magenta", "📥 Collector: Starting to collect results\n")
    divisible_count = 0
    total_count = 0
    
    for result in results_channel
        if haskey(result, "summary")
            print_color("magenta", @sprintf("📥 Collector: Summary - Average value: %.2f\n", result["average"]))
        else
            total_count += 1
            if result["divisible_by_3"]
                divisible_count += 1
            end
            
            print_color("magenta", "📥 Collector: Collected result for item $(result["id"])\n")
        end
        yield()  # Cooperative multitasking
    end
    
    percentage = total_count > 0 ? (divisible_count / total_count) * 100 : 0
    print_color("magenta", @sprintf("📥 Collector: Final results - %d/%d (%.1f%%) values divisible by 3\n", 
                divisible_count, total_count, percentage))
    print_color("magenta", "📥 Collector: Finished collecting results\n")
end

function run_pipeline(item_count::Int)
    print_color("blue", "🚀 Pipeline: Starting with $item_count items\n")
    
    # Create buffered channels for communication between stages
    raw_data_channel = Channel{Dict}(5)       # Generator -> Transformer
    transformed_channel = Channel{Dict}(5)    # Transformer -> Analyzer
    results_channel = Channel{Dict}(5)        # Analyzer -> Collector
    
    # Start the pipeline stages as tasks
    @sync begin
        @async data_generator(raw_data_channel, item_count)
        @async data_transformer(raw_data_channel, transformed_channel)
        @async data_analyzer(transformed_channel, results_channel)
        @async collector(results_channel)
    end
    
    print_color("blue", "🏁 Pipeline: Processing complete\n")
end

# Run the pipeline with 10 items
println("Starting data processing pipeline...")
run_pipeline(10)
