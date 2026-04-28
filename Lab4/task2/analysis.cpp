#include <mpi.h>
#include <iostream>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 4096
#define C 0.25
#define LEFT_TEMP 100.0
#define RIGHT_TEMP 0.0

static double array_mean(const double *arr, int len)
{
    double s = 0.0;
    for (int i = 0; i < len; i++)
    {
        s += arr[i];
    }

    return s / len;
}

int main(int argc, char *argv[])
{
    MPI_Init(&argc, &argv);

    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    // alhamin too
    int STEPS = 100;
    if (argc >= 2)
    {
        STEPS = atoi(argv[1]);
    }

    if (STEPS <= 0)
    {
        if (rank == 0)
        {
            printf("Error: STEPS must be positive.\n");
        }
        MPI_Finalize();
        return 1;
    }

    // tentsuu huvaarilalt
    if (N % size != 0)
    {
        if (rank == 0)
        {
            printf("Error: N = %d must be divisible by number of processes = %d\n", N, size);
        }
        MPI_Finalize();
        return 1;
    }

    int local_n = N / size;

    double *current = (double *)calloc(local_n + 2, sizeof(double));
    double *next = (double *)calloc(local_n + 2, sizeof(double));

    if (current == NULL || next == NULL)
    {
        printf("Rank %d: Memory allocation failed.\n", rank);
        MPI_Finalize();
        return 1;
    }

    // Ehnii nuhtsul
    for (int i = 1; i <= local_n; i++)
    {
        int global_index = rank * local_n + (i - 1);

        if (global_index == 0)
        {
            current[i] = LEFT_TEMP;
        }
        else if (global_index == N - 1)
        {
            current[i] = RIGHT_TEMP;
        }
        else
        {
            current[i] = 0.0;
        }
    }

    double t_start = MPI_Wtime();

    // baruun zuun hurshiin hariltsaa XD
    for (int step = 0; step < STEPS; step++)
    {
        double send_left = current[1];
        double send_right = current[local_n];

        double recv_left = LEFT_TEMP;
        double recv_right = RIGHT_TEMP;

        int left_rank = (rank == 0) ? MPI_PROC_NULL : rank - 1;
        int right_rank = (rank == size - 1) ? MPI_PROC_NULL : rank + 1;

        // baruunaas baruun luu
        MPI_Sendrecv(&send_right, 1, MPI_DOUBLE, right_rank, 0,
                     &recv_left, 1, MPI_DOUBLE, left_rank, 0,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        // zuunees zuun luu
        MPI_Sendrecv(&send_left, 1, MPI_DOUBLE, left_rank, 1,
                     &recv_right, 1, MPI_DOUBLE, right_rank, 1,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        current[0] = recv_left;
        current[local_n + 1] = recv_right;

        // finite difference method
        for (int i = 1; i <= local_n; i++)
        {
            int global_i = rank * local_n + (i - 1);

            if (global_i == 0)
            {
                next[i] = LEFT_TEMP;
            }
            else if (global_i == N - 1)
            {
                next[i] = RIGHT_TEMP;
            }
            else
            {
                next[i] = current[i] + C * (current[i - 1] - 2.0 * current[i] + current[i + 1]);
            }
        }

        double *tmp = current;
        current = next;
        next = tmp;
    }

    double t_end = MPI_Wtime();

    // local average ba global average
    double local_avg = array_mean(current + 1, local_n);
    double global_avg_sum = 0.0;

    MPI_Reduce(
        &local_avg,
        &global_avg_sum,
        1,
        MPI_DOUBLE,
        MPI_SUM,
        0,
        MPI_COMM_WORLD);

    double global_avg = 0.0;
    if (rank == 0)
    {
        global_avg = global_avg_sum / size;
    }

    // local temp iig rank 0 deer;
    double *full_temperature = NULL;

    if (rank == 0)
    {
        full_temperature = (double *)malloc(N * sizeof(double));

        if (full_temperature == NULL)
        {
            printf("Rank 0: Failed to allocate full_temperature array.\n");
            free(current);
            free(next);
            MPI_Finalize();
            return 1;
        }
    }

    MPI_Gather(
        current + 1,
        local_n,
        MPI_DOUBLE,
        full_temperature,
        local_n,
        MPI_DOUBLE,
        0,
        MPI_COMM_WORLD);

    // Process bolgon ehni ba suuliin 3 utgaa hevlene
    MPI_Barrier(MPI_COMM_WORLD);

    for (int r = 0; r < size; r++)
    {
        if (rank == r)
        {
            printf(
                "Rank %d | step: %d | first_few_points: [%.4f, %.4f, %.4f]"
                "  last_points: [%.4f, %.4f, %.4f]  Mean: %.4f\n",
                rank,
                STEPS,
                current[1],
                current[2],
                current[3],
                current[local_n - 2],
                current[local_n - 1],
                current[local_n],
                local_avg);
            fflush(stdout);
        }

        MPI_Barrier(MPI_COMM_WORLD);
    }


    //Rank 0 output.csv
    if (rank == 0)
    {
        FILE *fp = fopen("output.csv", "w");

        if (fp == NULL)
        {
            printf("Error: Could not create output.csv\n");
        }
        else
        {
            fprintf(fp, "position,temperature\n");

            for (int i = 0; i < N; i++)
            {
                fprintf(fp, "%d,%.10f\n", i, full_temperature[i]);
            }

            fclose(fp);
            printf("\noutput.csv file created successfully.\n");
        }

        printf("\n--------------------------------------\n");
        printf("Total steps          : %d\n", STEPS);
        printf("Total points N       : %d\n", N);
        printf("Number of processes  : %d\n", size);
        printf("Local points/process : %d\n", local_n);
        printf("Thermal diffusivity C: %.2f\n", C);
        printf("Left BC              : %.1f\n", LEFT_TEMP);
        printf("Right BC             : %.1f\n", RIGHT_TEMP);
        printf("Global average T     : %.6f\n", global_avg);
        printf("Time sec             : %.6f\n", t_end - t_start);
        printf("--------------------------------------\n");

        free(full_temperature);
    }

    free(current);
    free(next);

    MPI_Finalize();
    return 0;
}