#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char *argv[])
{
    long points = 10;
    long in_circle = 0;
    int rank, size;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    long per_process = points / size;
    srand(time(NULL) + rank);

    for (long i = 0; i < per_process; i++)
    {
        double x = (double)rand() / RAND_MAX * 2 - 1.0;
        double y = (double)rand() / RAND_MAX * 2 - 1.0;

        if (x * x + y * y <= 1.0)
        {
            in_circle++;
        }
    }

    if (rank != 0)
    {
        MPI_Send(&in_circle, 1, MPI_LONG, 0, 0, MPI_COMM_WORLD);
    }
    else
    {
        long total_hits = in_circle;
        long received_hits;
        for (int i = 1; i < size; i++)
        {
            MPI_Recv(&received_hits, 1, MPI_LONG, i, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
            total_hits += received_hits;
        }

        double pi = 4.0 * total_hits / points;
        printf("Estimated Pi: %f\n", pi);
    }

    MPI_Finalize();
    return 0;
}

// mpicc -o test test.cpp
// mpirun -np 4 ./test