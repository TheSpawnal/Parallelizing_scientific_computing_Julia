# Implement a function ex1(a) that finds the largest item in the array a. 
# It should return the largest item and its corresponding position in the array. 
# If there are multiple maximal elements, then the first one will be returned. 
# Assume that the array is not empty. Implement the function in the next cell. 
# Test your implementation with the other one.



function ex1(a)
    j = 1
    m = a[j]
    for (i,ai) in enumerate(a)
        if m < ai
            m = ai
            j = i
        end
    end
    (m,j)
end

using Test
arr = [3,4,7,3,1,7,2]
@test ex1(arr) == (7,3)