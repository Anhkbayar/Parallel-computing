#include <iostream>
#include <chrono>
#include <fstream>
#include <thread>
#include <vector>
using namespace std;

#define SIZE 80000000
#define VALUE 1.0
#define RUNS 13
#define THREADS 16

double arr[SIZE];

void part_sum(long start, long end, double &sum)
{
    double thread_sum = 0.0;
    for (long i = start; i < end; i++)
    {
        thread_sum += arr[i];
    }

    sum = thread_sum;
}

double thread_sum(int thread_num)
{
    vector<thread> threads(thread_num);
    vector<double> partial(thread_num, 0.0);

    long chunk = SIZE / thread_num;

    for (int i = 0; i < thread_num; i++)
    {
        long start = i * chunk;
        long end = (i == thread_num - 1) ? SIZE : start + chunk;

        threads[i] = thread(part_sum, start, end, ref(partial[i]));
    }

    for (auto &th : threads)
        th.join();

    double sum = 0.0;
    for (auto &p : partial)
        sum += p;

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

        double result = thread_sum(THREADS);

        auto end = std::chrono::steady_clock::now();

        auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

        cout <<run_i << " ur dun "<< result << "\n";

        file << "sum,"
             << "threads,"
             << THREADS << ","
             << SIZE << ","
             << run_i << ","
             << elapsed_ms << "\n";
    }

    file.close();
    return 0;
};