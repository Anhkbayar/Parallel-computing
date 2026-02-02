#include <iostream>
#include <chrono>
#include <fstream>
using namespace std;

#define SIZE 80000000
#define VALUE 1.0
#define RUNS 13

double arr[SIZE];

double serial()
{
    double sum = 0.0;
    for (long i = 0; i < SIZE; i++)
    {
        sum += arr[i];
    }
    return sum;
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

        double result = serial();

        auto end = std::chrono::steady_clock::now();

        auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

        cout <<run_i << " ur dun "<< result << "\n";

        file << "sum,"
             << "serial,"
             << 1 << ","
             << SIZE << ","
             << run_i << ","
             << elapsed_ms << "\n";
    }


    file.close();
    return 0;
};