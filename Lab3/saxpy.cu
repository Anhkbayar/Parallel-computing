#include <stdio.h>
#include <cuda_runtime.h>
#include <chrono>

/**
 * ДААЛГАВАР 1: CUDA Kernel бичих
 * Энэ функц нь GPU-ийн thread бүр дээр зэрэг ажиллана.
 * Томьёо: result[i] = alpha * x[i] + y[i]
 */
__global__ void saxpy_kernel(int N, float alpha, float *x, float *y, float *result)
{
    // Энд thread-ийн глобал индексийг тооцоолж гаргах хэрэгтэй
    // int index = ...

    // Индекс N-ээс бага үед тооцооллыг хийнэ
    // if (index < N) { ... }
}

void run_saxpy(int N, float alpha, float *host_x, float *host_y, float *host_result)
{
    int size = N * sizeof(float);
    float *device_x, *device_y, *device_result;

    auto totalStart = std::chrono::high_resolution_clock::now();

    /**
     * ДААЛГАВАР 2: GPU дээр санах ой хуваарилах (cudaMalloc)
     * device_x, device_y, device_result-д зориулж 'size' хэмжээтэй зай авна.
     */
    // cudaMalloc(...);

    /**
     * ДААЛГАВАР 3: Өгөгдлийг CPU-ээс GPU рүү хуулах (cudaMemcpy)
     * host_x -> device_x, host_y -> device_y
     */
    // cudaMemcpy(...);

    // Блок болон Thread-ийн тоог тохируулах
    const int threadsPerBlock = 256;
    const int blocks = (N + threadsPerBlock - 1) / threadsPerBlock;

    // Kernel хугацаа хэмжих бэлтгэл
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    cudaEventRecord(start);

    /**
     * ДААЛГАВАР 4: Kernel-ийг дуудах (Launch Kernel)
     * <<<blocks, threadsPerBlock>>> тохиргоотойгоор saxpy_kernel-ийг ажиллуулна.
     */
    // saxpy_kernel<<<...>>>(...);

    cudaEventRecord(stop);
    cudaEventSynchronize(stop);

    float kernelMs = 0;
    cudaEventElapsedTime(&kernelMs, start, stop);

    /**
     * ДААЛГАВАР 5: Үр дүнг GPU-ээс CPU рүү буцааж хуулах
     * device_result -> host_result
     */
    // cudaMemcpy(...);

    auto totalEnd = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> totalMs = totalEnd - totalStart;

    // Үр дүнг хэвлэх
    printf("--- CUDA SAXPY Result ---\n");
    printf("Total time (including memory transfer): %.3f ms\n", totalMs.count());
    printf("Kernel execution time:                 %.3f ms\n", kernelMs);

    // Чөлөөлөх
    cudaFree(device_x);
    cudaFree(device_y);
    cudaFree(device_result);
    cudaEventDestroy(start);
    cudaEventDestroy(stop);
}

int main()
{
    int N = 1 << 20; // 1,048,576 элемент
    float alpha = 2.0f;

    // CPU санах ой хуваарилах
    float *x = (float *)malloc(N * sizeof(float));
    float *y = (float *)malloc(N * sizeof(float));
    float *result = (float *)malloc(N * sizeof(float));

    // Өгөгдөл бэлдэх
    for (int i = 0; i < N; i++)
    {
        x[i] = 1.0f;
        y[i] = 2.0f;
    }

    run_saxpy(N, alpha, x, y, result);

    // Шалгалт (Verification)
    bool success = true;
    for (int i = 0; i < 100; i++)
    { // Эхний 100 элементийг шалгах
        if (result[i] != 4.0f)
        {
            success = false;
            break;
        }
    }

    if (success)
        printf("Verification: SUCCESS!\n");
    else
        printf("Verification: FAILED! (Check your kernel or copy logic)\n");

    free(x);
    free(y);
    free(result);
    return 0;
}