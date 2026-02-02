#include <iostream>
#include <chrono>
#include <fstream>
#include <omp.h>
#include <cmath>
using namespace std;

#define SIZE 80000000
#define VALUE 1.0
#define RUNS 13
#define THREADS 16

double arr[SIZE];

bool allSame(double arr[], int n)
{
    double first = arr[0];

    for (int i = 1; i < n; i++)
        if (arr[i] != first)
            return 0;
    return 1;
}

void omp()
{
#pragma omp parallel for num_threads(THREADS)
    for (long i = 0; i < SIZE; i++)
    {
        arr[i] = std::sin(arr[i]) * 0.5 + 0.25;
    }
}

int main()
{
    for (int i = 0; i < SIZE; i++)
    {
        arr[i] = VALUE;
    }

    // int threads = 1;

    std::ofstream file("../results.csv", std::ios::app);

    for (int run_i = 1; run_i <= RUNS; run_i++)
    {
        auto start = std::chrono::steady_clock::now();

        omp();

        auto end = std::chrono::steady_clock::now();

        auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

        cout << "Buh toonuud " << allSame(arr, SIZE) << " Adil " << arr[0] << "\n";

        file << "equation,"
             << "OMP,"
             << THREADS << ","
             << SIZE << ","
             << run_i << ","
             << elapsed_ms << "\n";
    }

    file.close();
    return 0;
};