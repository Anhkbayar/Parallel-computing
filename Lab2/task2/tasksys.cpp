#include "tasksys.h"
#include <thread>
#include <atomic>
IRunnable::~IRunnable() {}

ITaskSystem::ITaskSystem(int num_threads) {}
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
    // 1st problem to get checked by TEACHER.............
}


TaskSystemParallelSpawn::~TaskSystemParallelSpawn() {}
void TaskSystemParallelSpawn::run(IRunnable *runnable, int num_total_tasks)
{
    int num_threads = std::thread::hardware_concurrency();
    if (num_threads == 0)
        num_threads = 4;

    std::vector<std::thread> threads;

    for (int t = 0; t < num_threads; t++)
    {
        threads.emplace_back([=]() {
            for (int i = t; i < num_total_tasks; i += num_threads)
            {
                runnable->runTask(i, num_total_tasks);
            }
        });
    }

    for (auto &th : threads)
        th.join();
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

    //
    // TODO: CSM306 student implementations may decide to perform setup
    // operations (such as thread pool construction) here.
    // Implementations are free to add new class member variables
    // (requiring changes to tasksys.h).
    // 2nd problem to get checked b tEACHER.............
    //

const char *TaskSystemParallelThreadPoolSpinning::name()
{
    return "Parallel + Thread Pool + Spin";
}

TaskSystemParallelThreadPoolSpinning::
TaskSystemParallelThreadPoolSpinning(int num_threads)
    : ITaskSystem(num_threads),
      num_threads(num_threads),
      currentRunnable(nullptr),
      totalTasks(0),
      nextTask(0),
      finishedTasks(0),
      stop(false)
{
    // Create worker threads (thread pool)
    for (int i = 0; i < num_threads; i++)
    {
        workers.emplace_back([this]() {
            while (!stop)
            {
                // Atomically get next task index
                int task = nextTask.fetch_add(1);

                // If task is valid, execute it
                if (task < totalTasks)
                {
                    currentRunnable->runTask(task, totalTasks);
                    finishedTasks.fetch_add(1);
                }
                // Otherwise keep spinning
            }
        });
    }
}

TaskSystemParallelThreadPoolSpinning::~TaskSystemParallelThreadPoolSpinning() {
    stop = true;

    for (auto &t : workers)
        t.join();
}

void TaskSystemParallelThreadPoolSpinning::run(IRunnable *runnable, int num_total_tasks)
{

    //
    // TODO: CSM306 students will modify the implementation of this
    // method in Part A.  The implementation provided below runs all
    // tasks sequentially on the calling thread.
    //

    currentRunnable = runnable;
    totalTasks = num_total_tasks;
    nextTask = 0;
    finishedTasks = 0;

    // Wait until all tasks are finished
    while (finishedTasks.load() < totalTasks)
    {
        // spinning wait
    }
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

TaskSystemParallelThreadPoolSleeping::TaskSystemParallelThreadPoolSleeping(int num_threads)
    : ITaskSystem(num_threads),
      num_threads(num_threads),
      stop(false),
      nextJobID(0),
      unfinishedJobs(0)
{
    //
    // TODO: CSM306 student implementations may decide to perform setup
    // operations (such as thread pool construction) here.
    // Implementations are free to add new class member variables
    // (requiring changes to tasksys.h).
    //

    for (int i = 0; i < num_threads; i++)
    {
        workers.emplace_back([this]() { workerLoop(); });
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
        std::lock_guard<std::mutex> lock(mtx);
        stop = true;
    }

    cv_work.notify_all();

    for (auto &t : workers)
    {
        t.join();
    }
}

void TaskSystemParallelThreadPoolSleeping::workerLoop()
{
    while (true)
    {
        JobGroup *job = nullptr;
        int task = -1;

        {
            std::unique_lock<std::mutex> lock(mtx);

            cv_work.wait(lock, [this]() {
                return stop || !readyQueue.empty();
            });

            if (stop)
                return;

            while (!readyQueue.empty())
            {
                JobGroup *candidate = readyQueue.front();

                if (candidate->nextTask < candidate->totalTasks)
                {
                    job = candidate;
                    task = candidate->nextTask;
                    candidate->nextTask++;

                    // If there are still tasks left after taking one,
                    // keep the job in queue for other workers
                    if (candidate->nextTask >= candidate->totalTasks)
                    {
                        readyQueue.pop();
                    }

                    break;
                }
                else
                {
                    readyQueue.pop();
                }
            }

            if (job == nullptr)
                continue;
        }

        // Run the task without holding the mutex
        job->runnable->runTask(task, job->totalTasks);

        {
            std::lock_guard<std::mutex> lock(mtx);

            job->finishedTasks++;

            // If there are still unassigned tasks, requeue it
            if (job->nextTask < job->totalTasks)
            {
                readyQueue.push(job);
                cv_work.notify_one();
            }

            if (job->finishedTasks == job->totalTasks && !job->completed)
            {
                finishJob(job);
            }
        }
    }
}

void TaskSystemParallelThreadPoolSleeping::finishJob(JobGroup *job)
{
    job->completed = true;
    unfinishedJobs--;

    // Unlock dependent jobs
    for (TaskID depID : job->dependents)
    {
        auto it = jobs.find(depID);
        if (it != jobs.end())
        {
            JobGroup *child = it->second.get();
            child->remainingDeps--;

            if (child->remainingDeps == 0)
            {
                readyQueue.push(child);
                cv_work.notify_all();
            }
        }
    }

    if (unfinishedJobs == 0)
    {
        cv_done.notify_all();
    }
}

void TaskSystemParallelThreadPoolSleeping::run(IRunnable *runnable, int num_total_tasks)
{
    //
    // TODO: CSM306 students will modify the implementation of this
    // method in Parts A and B.  The implementation provided below runs all
    // tasks sequentially on the calling thread.
    //

    runAsyncWithDeps(runnable, num_total_tasks, {});
    sync();
}

TaskID TaskSystemParallelThreadPoolSleeping::runAsyncWithDeps(IRunnable *runnable, int num_total_tasks,
                                                              const std::vector<TaskID> &deps)
{
    //
    // TODO: CSM306 students will implement this method in Part B.
    //

    std::lock_guard<std::mutex> lock(mtx);

    TaskID id = nextJobID++;
    auto job = std::make_shared<JobGroup>(id, runnable, num_total_tasks);

    unfinishedJobs++;
    jobs[id] = job;

    int unresolved = 0;

    for (TaskID dep : deps)
    {
        auto it = jobs.find(dep);
        if (it != jobs.end() && !it->second->completed)
        {
            unresolved++;
            it->second->dependents.push_back(id);
        }
    }

    job->remainingDeps = unresolved;

    if (job->remainingDeps == 0)
    {
        readyQueue.push(job.get());
        cv_work.notify_all();
    }

    return id;
}

void TaskSystemParallelThreadPoolSleeping::sync()
{
    //
    // TODO: CSM306 students will modify the implementation of this method in Part B.
    //

    std::unique_lock<std::mutex> lock(mtx);
    cv_done.wait(lock, [this]() { return unfinishedJobs == 0; });
}