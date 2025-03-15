#include <math.h>
#include <stdio.h>
#include "mpi.h"

int main(int argc, char *argv[])
{
  int done = 0, n, myid, numprocs, i;
  double mypi, pi, h, sum, x, t0, t1;

  MPI_Init(&argc,&argv);
  MPI_Comm_size(MPI_COMM_WORLD,&numprocs);
  MPI_Comm_rank(MPI_COMM_WORLD,&myid);
  while (!done) {
    if (myid == 0) {
      printf("Enter the number of intervals: (0 quits) ");
      fflush(stdout);
      scanf("%d",&n);
    }
    MPI_Bcast(&n, 1, MPI_INT, 0, MPI_COMM_WORLD);
    if (n == 0) break;
    
    t0 = MPI_Wtime();
    /* integrate 4/(1 + x*x) from 0 to 1 */
    h   = 1.0 / (double) n;
    sum = 0.0;
    for (i = myid + 1; i <= n; i += numprocs) {
      x = h * ((double)i - 0.5);
      sum += 4.0 / (1.0 + x*x);
    }
    mypi = h * sum;
        
    MPI_Reduce(&mypi, &pi, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
        
    t1 = MPI_Wtime();
    if (myid == 0) {
      printf("elapsed time is %.4f seconds\n", t1-t0);
      printf("pi is approximately %.16f, Error is %.16f\n",
           pi, fabs(pi - M_PI));
    }
  }
  MPI_Finalize();
  return 0;
}