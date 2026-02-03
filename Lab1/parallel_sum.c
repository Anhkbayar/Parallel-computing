#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <omp.h>
//export OMP_NUM_THREADS=2
#define THREADS 16
int main()
{
    #pragma omp parallel num_threads(THREADS)
    {
        printf("Hello world");
    }
    const size_t size = 80000000;
    double *a = (double *)malloc(size * sizeof(double));
    for (size_t i = 0; i < size; i++)
    {
        a[i] = 1.0;
    }
    for (int i = 0; i < 3; i++)
    {
        double temp_sum = 0.0;
        for (size_t j = 0; j < size; j++)
        {
            temp_sum += a[j];
        }
    }

    const int runs = 10;
    double timings[10];
    double final_sum = 0.0;
    for (int i = 0; i < runs; i++)
    {
        struct timespec start, end, elapsed;
        double current_sum = 0.0;
        clock_gettime(CLOCK_MONOTONIC, &start);
        #pragma omp parallel for reduction(+ :current_sum) num_threads(THREADS)
        for (size_t j = 0; j < size; j++)
        {
            current_sum += a[j];
        }
        final_sum = current_sum;
        clock_gettime(CLOCK_MONOTONIC, &end);

        double elapsed_ms = (end.tv_sec - start.tv_sec) * 1000.0 +
                            (end.tv_nsec - start.tv_nsec) / 1000000.0;

        timings[i] = elapsed_ms;
        printf("Run %d: %.2f ms\n", i, elapsed_ms);
    }
    double total_time = 0.0;
    for (int i = 0; i < runs; i++)
    {
        total_time += timings[i];
    }
    double mean_time = total_time / runs;
    printf("niilber: %.1f\n", final_sum);
    printf("dundaj: %.2f ms\n", mean_time);
    free(a);
    return 0;
}