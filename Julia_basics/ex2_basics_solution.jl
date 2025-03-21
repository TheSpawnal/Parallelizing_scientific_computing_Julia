# implement a function ex2(f,g) that takes two functions f(x) and g(x) and returns a 
    # new function h(x) representing the sum of f and g, i.e., h(x)=f(x)+g(x).

ex2(f,g) = x -> f(x) + g(x)
   

h = ex2(sin,cos)
xs = LinRange(0,2π,100)
@test all(x-> h(x) == sin(x)+cos(x), xs)