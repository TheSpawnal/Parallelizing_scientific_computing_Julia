# Implement this "simple" algorithm (the telephone game):

# Worker 1 generates a message (an integer). 
# Worker 1 sends the message to worker 2. 
# Worker 2 receives the message, increments the message by 1, and sends the result to worker 3. 
# Worker 3 receives the message, increments the message by 1, and sends the result to worker 4. 
# Etc. The last worker sends back the message to worker 1 closing the ring. 

f = () -> Channel{Int}(1)
chnls = [RemoteChannel(f, w) for w in workers()]
n_workers = length(workers())

@sync for (iw, w) in enumerate(workers())
    @spawnat w begin
        # Current worker's channel for sending
        chnl_snd = chnls[iw]
        
        if w == workers()[1]  # First worker starts the process
            # Receive from last worker to close the ring
            chnl_rcv = chnls[n_workers]
            
            # Initialize message
            msg = 0
            println("Worker $w: Starting with msg = $msg")
            
            # Send to next worker
            put!(chnl_snd, msg)
            
            # Wait for message to come full circle
            msg = take!(chnl_rcv)
            println("Worker $w: Received final msg = $msg")
        else
            # For other workers, receive from previous worker
            prev_idx = iw - 1
            chnl_rcv = chnls[prev_idx]
            
            # Get message, increment, and send
            msg = take!(chnl_rcv)
            msg += 1
            println("Worker $w: Received msg = $(msg-1), sending msg = $msg")
            
            # Send to next worker (or back to first if last)
            put!(chnl_snd, msg)
        end
    end
end