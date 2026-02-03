#include <stdio.h>
#include <stdlib.h>
#include <time.h>
int main()
{
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
}