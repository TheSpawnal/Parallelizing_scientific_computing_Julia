"""
A priority-based task scheduler that demonstrates how to implement more complex task management using Julia's async primitives.

This example implements a more sophisticated task scheduler that executes tasks based on priority levels. 
It demonstrates how to manage tasks with different importance levels and coordinate their execution.
The code shows complex task management patterns including task creation, scheduling, execution monitoring, and result collection with proper error handling.
"""

using Printf

# Define ANSI color codes for pretty printing
const COLORS = Dict(
    :reset => "\e[0m",
    :red => "\e[31m",
    :green => "\e[32m",
    :yellow => "\e[33m",
    :blue => "\e[34m",
    :magenta => "\e[35m",
    :cyan => "\e[36m",
    :gray => "\e[90m"
)

# Create colored print function
function cprint(color, message)
    print(get(COLORS, color, COLORS[:reset]), message, COLORS[:reset])
end

# Define priority levels
@enum Priority begin
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4
end

# Define a task with priority
mutable struct PriorityTask
    id::String
    name::String
    priority::Priority
    function_to_run::Function
    execution_time::Float64  # estimated execution time in seconds
    status::Symbol  # :pending, :running, :completed, :failed
    result::Any
    error::Any
    
    # Constructor
    function PriorityTask(id, name, priority, func, execution_time)
        return new(id, name, priority, func, execution_time, :pending, nothing, nothing)
    end
end

# PriorityTaskScheduler manages and executes tasks based on their priority
mutable struct PriorityTaskScheduler
    tasks::Dict{String, PriorityTask}  # task_id => task
    pending_tasks::Channel{PriorityTask}
    results_channel::Channel{PriorityTask}
    max_concurrent::Int
    running_count::Ref{Int}
    
    # Constructor
    function PriorityTaskScheduler(max_concurrent::Int = 4)
        return new(
            Dict{String, PriorityTask}(),
            Channel{PriorityTask}(100),
            Channel{PriorityTask}(100),
            max_concurrent,
            Ref{Int}(0)
        )
    end
end

# Add a task to the scheduler
function add_task!(scheduler::PriorityTaskScheduler, task::PriorityTask)
    scheduler.tasks[task.id] = task
    cprint(:cyan, @sprintf("📝 Added task '%s' (ID: %s, Priority: %s)\n", 
           task.name, task.id, task.priority))
    return task.id
end

# Schedule pending tasks based on priority
function schedule_pending_tasks!(scheduler::PriorityTaskScheduler)
    # Get all pending tasks
    pending = filter(t -> t.status == :pending, collect(values(scheduler.tasks)))
    
    # Sort by priority (higher priority first)
    sort!(pending, by = t -> Int(t.priority), rev = true)
    
    # Put them in the pending channel
    for task in pending
        put!(scheduler.pending_tasks, task)
        task.status = :scheduled
        cprint(:blue, @sprintf("🔄 Scheduled task '%s' (Priority: %s)\n", 
               task.name, task.priority))
    end
end

# Execute a single task
function execute_task!(scheduler::PriorityTaskScheduler, task::PriorityTask)
    task.status = :running
    scheduler.running_count[] += 1
    
    cprint(:yellow, @sprintf("▶️ Executing task '%s' (ID: %s, Priority: %s)\n", 
           task.name, task.id, task.priority))
    
    # Create a task to run the function
    @async begin
        try
            # Execute the task function
            start_time = time()
            task.result = task.function_to_run()
            execution_time = time() - start_time
            
            task.status = :completed
            cprint(:green, @sprintf("✅ Completed task '%s' in %.2f seconds (estimated: %.2f)\n", 
                   task.name, execution_time, task.execution_time))
        catch e
            task.error = e
            task.status = :failed
            cprint(:red, @sprintf("❌ Failed task '%s': %s\n", 
                   task.name, e))
        finally
            # Decrement running count and put the task in results channel
            scheduler.running_count[] -= 1
            put!(scheduler.results_channel, task)
            yield()  # Allow other tasks to run
        end
    end
end

# Run the scheduler
function run_scheduler!(scheduler::PriorityTaskScheduler)
    # Start by scheduling all pending tasks
    schedule_pending_tasks!(scheduler)
    
    # Start task execution worker
    execution_task = @async begin
        while isopen(scheduler.pending_tasks) || scheduler.running_count[] > 0
            # If we have capacity and pending tasks, execute one
            if scheduler.running_count[] < scheduler.max_concurrent && isopen(scheduler.pending_tasks)
                try
                    task = take!(scheduler.pending_tasks)
                    execute_task!(scheduler, task)
                catch e
                    if isa(e, InvalidStateException) && e.state == :closed
                        # Channel is closed, which is expected
                        break
                    else
                        # Unexpected error
                        cprint(:red, @sprintf("⚠️ Error in scheduler: %s\n", e))
                    end
                end
            end
            yield()  # Allow other tasks to run
            sleep(0.01)  # Small delay to prevent CPU spinning
        end
        cprint(:magenta, "🏁 All tasks have been processed\n")
    end
    
    # Start results collector
    results_task = @async begin
        completed = 0
        failed = 0
        
        while isopen(scheduler.results_channel) || scheduler.running_count[] > 0
            try
                task = take!(scheduler.results_channel)
                if task.status == :completed
                    completed += 1
                elseif task.status == :failed
                    failed += 1
                end
            catch e
                if isa(e, InvalidStateException) && e.state == :closed
                    # Channel is closed, which is expected
                    break
                else
                    # Unexpected error
                    cprint(:red, @sprintf("⚠️ Error in results collector: %s\n", e))
                end
            end
            yield()  # Allow other tasks to run
        end
        
        total = completed + failed
        cprint(:cyan, "📊 Task execution summary:\n")
        cprint(:green, @sprintf("   ✅ %d completed (%.1f%%)\n", completed, completed/total*100))
        cprint(:red, @sprintf("   ❌ %d failed (%.1f%%)\n", failed, failed/total*100))
    end
    
    # Wait for both the executor and collector to finish
    @sync begin
        @async begin
            fetch(execution_task)
            close(scheduler.results_channel)
        end
        @async fetch(results_task)
    end
end

# Create a function that simulates work with a given duration and success probability
function create_work_function(duration, success_probability=0.9)
    return function()
        # Simulate work by sleeping
        remaining = duration
        chunks = 10
        chunk_size = duration / chunks
        
        for i in 1:chunks
            if i < chunks
                sleep(chunk_size)
                remaining -= chunk_size
                yield()  # Allow other tasks to run
            else
                # Last chunk
                sleep(remaining)
            end
        end
        
        # Simulate potential failure
        if rand() > success_probability
            error("Simulated random failure")
        end
        
        # Return some result
        return "Completed after $(duration) seconds"
    end
end

# Demo: Create a task scheduler and run various tasks with different priorities
function run_demo()
    cprint(:magenta, "🚀 Starting Priority Task Scheduler Demo\n")
    
    # Create the scheduler with max 3 concurrent tasks
    scheduler = PriorityTaskScheduler(3)
    
    # Add various tasks with different priorities
    add_task!(scheduler, PriorityTask("task1", "Quick low priority task", LOW, 
              create_work_function(1.0, 0.95), 1.0))
    
    add_task!(scheduler, PriorityTask("task2", "Medium task", MEDIUM, 
              create_work_function(2.5, 0.9), 2.5))
    
    add_task!(scheduler, PriorityTask("task3", "Long high priority task", HIGH, 
              create_work_function(4.0, 0.8), 4.0))
    
    add_task!(scheduler, PriorityTask("task4", "Critical task", CRITICAL, 
              create_work_function(1.5, 0.99), 1.5))
    
    add_task!(scheduler, PriorityTask("task5", "Another medium task", MEDIUM, 
              create_work_function(3.0, 0.7), 3.0))
    
    add_task!(scheduler, PriorityTask("task6", "Likely to fail task", LOW, 
              create_work_function(2.0, 0.3), 2.0))
    
    add_task!(scheduler, PriorityTask("task7", "Quick critical task", CRITICAL, 
              create_work_function(1.2, 0.95), 1.2))
    
    add_task!(scheduler, PriorityTask("task8", "Medium high priority task", HIGH, 
              create_work_function(3.5, 0.85), 3.5))
    
    # Run the scheduler
    cprint(:magenta, "⏳ Running the scheduler with $(length(scheduler.tasks)) tasks\n")
    run_scheduler!(scheduler)
    
    # Show final status of all tasks
    cprint(:magenta, "📋 Final task status:\n")
    tasks_by_priority = sort(collect(values(scheduler.tasks)), 
                            by = t -> (Int(t.priority), t.name), rev = true)
    
    for task in tasks_by_priority
        status_color = task.status == :completed ? :green : 
                      (task.status == :failed ? :red : :yellow)
        status_emoji = task.status == :completed ? "✅" : 
                      (task.status == :failed ? "❌" : "⏳")
        
        cprint(status_color, @sprintf("%s %-10s | %-20s | %-8s | %s\n", 
              status_emoji, task.id, task.name, task.priority, task.status))
    end
    
    cprint(:magenta, "🏁 Demo completed\n")
end

# Run the demo
run_demo()
