
"""
A simulation of an asynchronous web scraper that handles multiple requests,
demonstrating tasks with yield and error handling.
This example simulates a web scraper that fetches multiple URLs concurrently. 
It demonstrates error handling in asynchronous tasks, variable execution times, 
and collecting results from multiple concurrent operations.
The code highlights how tasks can run in the background while handling different 
response times and potential errors without blocking the main application.
"""

using Printf
using Random

# Define colorful output function
function colorize(message, color)
    colors = Dict(
        "red" => "\e[31m",
        "green" => "\e[32m",
        "yellow" => "\e[33m",
        "blue" => "\e[34m",
        "magenta" => "\e[35m",
        "cyan" => "\e[36m",
        "reset" => "\e[0m"
    )
    return "$(colors[color])$(message)$(colors["reset"])"
end

# Simulate a web request with variable response time and possible failures
function fetch_url(url)
    # Simulate network latency
    delay = rand() * 2
    
    # Simulate potential connection errors (10% chance)
    if rand() < 0.1
        error("Connection timeout for URL: $url")
    end
    
    # Simulate server processing
    sleep(delay)
    
    # Simulate HTTP response codes (20% chance of non-200)
    status_code = rand() < 0.2 ? rand([404, 500, 503]) : 200
    
    # Simulate response size
    content_size = rand(500:10000)
    
    return Dict(
        "url" => url,
        "status" => status_code,
        "delay" => delay,
        "content_size" => content_size
    )
end

# Process a single URL with error handling
function process_url(url, results_channel)
    task_id = randstring(4)
    println(colorize("🌐 Task $task_id: Starting to fetch $url", "blue"))
    
    try
        response = fetch_url(url)
        println(colorize("✅ Task $task_id: Fetched $url ($(response["status"]), $(response["content_size"]) bytes) in $(round(response["delay"], digits=2))s", 
                        response["status"] == 200 ? "green" : "yellow"))
        put!(results_channel, response)
    catch e
        println(colorize("❌ Task $task_id: Error fetching $url: $(e.msg)", "red"))
        put!(results_channel, Dict("url" => url, "error" => e.msg))
    end
end

# Process multiple URLs concurrently
function run_scraper(urls)
    println(colorize("🚀 Web Scraper: Starting to process $(length(urls)) URLs", "magenta"))
    
    # Channel for collecting results
    results = Channel{Dict}(length(urls))
    
    # Start a task for each URL
    @sync begin
        for url in urls
            @async process_url(url, results)
            yield()  # Allow other tasks to run
        end
    end
    
    # Close the results channel
    close(results)
    
    # Analyze results
    successful = 0
    failed = 0
    total_size = 0
    total_time = 0.0
    
    for result in results
        if haskey(result, "error")
            failed += 1
        else
            successful += 1
            total_size += result["content_size"]
            total_time += result["delay"]
        end
    end
    
    println(colorize("📊 Web Scraper Results:", "cyan"))
    println(colorize(@sprintf("   - Success: %d (%.1f%%)", successful, successful/(successful+failed)*100), "cyan"))
    println(colorize(@sprintf("   - Failed: %d (%.1f%%)", failed, failed/(successful+failed)*100), "cyan"))
    
    if successful > 0
        println(colorize(@sprintf("   - Avg Size: %.1f KB", total_size/successful/1000), "cyan"))
        println(colorize(@sprintf("   - Avg Time: %.2f s", total_time/successful), "cyan"))
    end
    
    println(colorize("🏁 Web Scraper: Finished processing all URLs", "magenta"))
end

# Generate random URLs
function generate_urls(count)
    domains = ["example.com", "test.org", "sample.net", "demo.io", "mock.dev"]
    paths = ["home", "about", "products", "services", "contact", "blog", "article", "news"]
    
    urls = []
    for i in 1:count
        domain = rand(domains)
        path = join(rand(paths, rand(1:3)), "/")
        push!(urls, "https://www.$domain/$path")
    end
    
    return urls
end

# Run the simulated web scraper
println(colorize("Starting asynchronous web scraper simulation...", "cyan"))
urls = generate_urls(15)  # Generate 15 random URLs
run_scraper(urls)
