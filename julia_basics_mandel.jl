### Exercise 3
#Function `mandel` estimates if a given point `(x,y)` in the complex plane belongs to the 
#[Mandelbrot set](https://en.wikipedia.org/wiki/Mandelbrot_set).

function mandel(x,y,max_iters)
    z = Complex(x,y)
    c = z
    threshold=2
    for n in 1:max_iters
        if abs(z)>threshold
            return n-1
        end
        z = z^2 +c
    end
    max_iters
end

# If the value of `mandel` is less than `max_iters`, the point is provably outside the Mandelbrot set. 
# If `mandel` is equal to  `max_iters`, then the point is provably inside the set. The larger `max_iters`, 
# the better the quality of the estimate (the nicer will be your plot).

# Plot the value of function `mandel` for each pixel in a 2D grid of the box.
# $$(-1.7,0.7)\times(-1.2,1.2).$$
# Use a grid resolution of at least 1000 points in each direction and `max_iters` at least 10. 
# You can increase these values to get nicer plots. To plot the values use function `heatmap` from the Julia package `GLMakie`. 
# Use `LinRange` to divide the horizontal and vertical axes into pixels. See the documentation of these functions for help. 
# `GLMakie` is a GPU-accelerated plotting back-end for Julia. It is a large package and it can take some time to install and to generate the first plot. Be patient.
