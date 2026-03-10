#include <thread>
#include <vector>
#include <iostream>
#include <atomic>
#include <mutex>
#include "tasksys.h"

IRunnable::~IRunnable() {}

ITaskSystem::ITaskSystem(int nt) : num_threads(nt) {}
ITaskSystem::~ITaskSystem() {}

/*
 * ================================================================
 * Serial task system implementation
 * ================================================================
 */

const char *TaskSystemSerial::name()
{
    return "Serial";
}

TaskSystemSerial::TaskSystemSerial(int num_threads) : ITaskSystem(num_threads)
{
}

TaskSystemSerial::~TaskSystemSerial() {}

void TaskSystemSerial::run(IRunnable *runnable, int num_total_tasks)
{
    for (int i = 0; i < num_total_tasks; i++)
    {
        runnable->runTask(i, num_total_tasks);
    }
}

TaskID TaskSystemSerial::runAsyncWithDeps(IRunnable *runnable, int num_total_tasks,
                                          const std::vector<TaskID> &deps)
{
    // You do not need to implement this method.
    return 0;
}

void TaskSystemSerial::sync()
{
    // You do not need to implement this method.
    return;
}

/*
 * ================================================================
 * Parallel Task System Implementation
 * ================================================================
 */

const char *TaskSystemParallelSpawn::name()
{
    return "Parallel + Always Spawn";
}

TaskSystemParallelSpawn::TaskSystemParallelSpawn(int num_threads) : ITaskSystem(num_threads)
{
    //
    // TODO: CSM306 student implementations may decide to perform setup
    // operations (such as thread pool construction) here.
    // Implementations are free to add new class member variables
    // (requiring changes to tasksys.h).
    //
}

TaskSystemParallelSpawn::~TaskSystemParallelSpawn() {}

void TaskSystemParallelSpawn::run(IRunnable *runnable, int num_total_tasks)
{

    //
    // TODO: CSM306 students will modify the implementation of this
    // method in Part A.  The implementation provided below runs all
    // tasks sequentially on the calling thread.
    //
    // unsigned int n = std::thread::hardware_concurrency();
    // std::cout << n << " concurrent threads are supported.\n";

    int thread_count = std::min(num_threads, num_total_tasks);

    std::vector<std::thread> threads(thread_count);

    int chunk = (num_total_tasks + thread_count - 1) / thread_count;

    for (int i = 0; i < thread_count; i++)
    {
        int start = i * chunk;
        int end = std::min(start + chunk, num_total_tasks);

        threads[i] = std::thread([=]()
                                 {
            for(int i = start; i <end;i++){
                runnable->runTask(i, num_total_tasks);
            } });
    }

    for (int t = 0; t < thread_count; t++)
    {
        threads[t].join();
    }
}

TaskID TaskSystemParallelSpawn::runAsyncWithDeps(IRunnable *runnable, int num_total_tasks,
                                                 const std::vector<TaskID> &deps)
{
    // You do not need to implement this method.
    return 0;
}

void TaskSystemParallelSpawn::sync()
{
    // You do not need to implement this method.
    return;
}

/*
 * ================================================================
 * Parallel Thread Pool Spinning Task System Implementation
 * ================================================================
 */

const char *TaskSystemParallelThreadPoolSpinning::name()
{
    return "Parallel + Thread Pool + Spin";
}

TaskSystemParallelThreadPoolSpinning::TaskSystemParallelThreadPoolSpinning(int num_threads) : ITaskSystem(num_threads),
                                                                                              next_task(0),
                                                                                              tasks_done(0),
                                                                                              current_runnable(nullptr),
                                                                                              total_tasks(0),
                                                                                              has_work(false),
                                                                                              shutdown(false)
{
    //
    // TODO: CSM306 student implementations may decide to perform setup
    // operations (such as thread pool construction) here.
    // Implementations are free to add new class member variables
    // (requiring changes to tasksys.h).
    //
    for (int i = 0; i < num_threads; i++)
    {
        workers.emplace_back([this]()
                             {
            while(!shutdown){
                int task = next_task.fetch_add(1);

                if(task < total_tasks){
                    current_runnable->runTask(task, total_tasks);
                    tasks_done.fetch_add(1);
                }
            } });
    }
}

TaskSystemParallelThreadPoolSpinning::~TaskSystemParallelThreadPoolSpinning()
{
    shutdown = true;

    for (auto &t : workers)
    {
        t.join();
    }
}

void TaskSystemParallelThreadPoolSpinning::run(IRunnable *runnable, int num_total_tasks)
{

    //
    // TODO: CSM306 students will modify the implementation of this
    // method in Part A.  The implementation provided below runs all
    // tasks sequentially on the calling thread.
    //

    std::unique_lock<std::mutex> lock(mtx);
    current_runnable = runnable;
    total_tasks = num_total_tasks;
    next_task = 0;
    tasks_done = 0;
    has_work = true;

    while (tasks_done.load() < num_total_tasks)
    {
        std::this_thread::yield();
    }

    has_work = false;
}

TaskID TaskSystemParallelThreadPoolSpinning::runAsyncWithDeps(IRunnable *runnable, int num_total_tasks,
                                                              const std::vector<TaskID> &deps)
{
    // You do not need to implement this method.
    return 0;
}

void TaskSystemParallelThreadPoolSpinning::sync()
{
    // You do not need to implement this method.
    return;
}

/*
 * ================================================================
 * Parallel Thread Pool Sleeping Task System Implementation
 * ================================================================
 */

const char *TaskSystemParallelThreadPoolSleeping::name()
{
    return "Parallel + Thread Pool + Sleep";
}

TaskSystemParallelThreadPoolSleeping::TaskSystemParallelThreadPoolSleeping(int num_threads) : ITaskSystem(num_threads),
                                                                                              num_threads(num_threads),
                                                                                              currentRunnable(nullptr),
                                                                                              totalTasks(0),
                                                                                              next_task(0),
                                                                                              finished_tasks(0),
                                                                                              shutdown(false),
                                                                                              has_work(false)
{
    //
    // TODO: CSM306 student implementations may decide to perform setup
    // operations (such as thread pool construction) here.
    // Implementations are free to add new class member variables
    // (requiring changes to tasksys.h).
    //
    for (int i = 0; i < num_threads; i++)
    {
        workers.emplace_back([this]()
                             {
        while (true)
        {
            std::unique_lock<std::mutex> lock(mtx);

            cv_work.wait(lock, [this]() { return shutdown || has_work; });

            if (shutdown)
                return;

            while(true){
                int task = next_task;

                if(task >= totalTasks)
                    break;

                next_task++;

                lock.unlock();
                currentRunnable->runTask(task, totalTasks);
                lock.lock();

                finished_tasks++;
                if(finished_tasks == totalTasks){
                    has_work = false;
                    cv_done.notify_one();
                }
            }
        } });
    }
}

TaskSystemParallelThreadPoolSleeping::~TaskSystemParallelThreadPoolSleeping()
{
    //
    // TODO: CSM306 student implementations may decide to perform cleanup
    // operations (such as thread pool shutdown construction) here.
    // Implementations are free to add new class member variables
    // (requiring changes to tasksys.h).
    //
    {
        std::unique_lock<std::mutex> lock(mtx);
        shutdown = true;
    }

    cv_work.notify_all();

    for (auto &t : workers)
    {
        t.join();
    }
}

void TaskSystemParallelThreadPoolSleeping::run(IRunnable *runnable, int num_total_tasks)
{

    //
    // TODO: CSM306 students will modify the implementation of this
    // method in Parts A and B.  The implementation provided below runs all
    // tasks sequentially on the calling thread.
    //
    {
        std::lock_guard<std::mutex> lock(mtx);
        currentRunnable = runnable;
        totalTasks = num_total_tasks;
        next_task = 0;
        finished_tasks = 0;
        has_work = true;
    }

    cv_work.notify_all();

    std::unique_lock<std::mutex> lock(mtx);
    cv_done.wait(lock, [this]()
                 { return finished_tasks == totalTasks; });
}

TaskID TaskSystemParallelThreadPoolSleeping::runAsyncWithDeps(IRunnable *runnable, int num_total_tasks,
                                                              const std::vector<TaskID> &deps)
{

    //
    // TODO: CSM306 students will implement this method in Part B.
    //
    return 0;
}

void TaskSystemParallelThreadPoolSleeping::sync()
{

    //
    // TODO: CSM306 students will modify the implementation of this method in Part B.
    //
    return;
}