#include <stdio.h>
#include <cuda_runtime.h>
#include <chrono>

/**
 * 1.kernel
 * 2.cpu memory
 * 3.gpu memory
 * 4.h2d
 * 5.kernel run
 * 6.d2h
 */

/**
 * ДААЛГАВАР 1: CUDA Kernel бичих
 * Энэ функц нь GPU-ийн thread бүр дээр зэрэг ажиллана.
 * Томьёо: result[i] = alpha * x[i] + y[i]
 */
__global__ void saxpy_kernel(int N, float alpha, float *x, float *y, float *result)
{
    // Энд thread-ийн глобал индексийг тооцоолж гаргах хэрэгтэй
    // int index = ...
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    // Индекс N-ээс бага үед тооцооллыг хийнэ
    // if (index < N) { ... }
    if (i < N)
    {
        result[i] = alpha * x[i] + y[i];
    }
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
    cudaEvent_t malloc_start, malloc_end;
    cudaEventCreate(&malloc_start);
    cudaEventCreate(&malloc_end);

    cudaEventRecord(malloc_start);

    cudaMalloc((void **)&device_x, size);
    cudaMalloc((void **)&device_y, size);
    cudaMalloc((void **)&device_result, size);

    cudaEventRecord(malloc_end);
    cudaEventSynchronize(malloc_end);

    float malloc_ms = 0;
    cudaEventElapsedTime(&malloc_ms, malloc_start, malloc_end);

    /**
     * ДААЛГАВАР 3: Өгөгдлийг CPU-ээс GPU рүү хуулах (cudaMemcpy)
     * host_x -> device_x, host_y -> device_y
     */
    // cudaMemcpy(...);
    cudaEvent_t h2d_start, h2d_end;
    cudaEventCreate(&h2d_start);
    cudaEventCreate(&h2d_end);

    cudaEventRecord(h2d_start);

    cudaMemcpy(device_x, host_x, size, cudaMemcpyHostToDevice);
    cudaMemcpy(device_y, host_y, size, cudaMemcpyHostToDevice);

    cudaEventRecord(h2d_end);
    cudaEventSynchronize(h2d_end);

    float h2d_ms = 0;
    cudaEventElapsedTime(&h2d_ms, h2d_start, h2d_end);

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
    // auto kernelStart = std::chrono::high_resolution_clock::now();

    saxpy_kernel<<<blocks, threadsPerBlock>>>(N, alpha, device_x, device_y, device_result);

    cudaDeviceSynchronize();

    // auto kernelEnd = std::chrono::high_resolution_clock::now();
    // std::chrono::duration<double, std::milli> kernelDuration = kernelEnd - kernelStart;

    cudaEventRecord(stop);
    cudaEventSynchronize(stop);

    float kernelMs = 0;
    cudaEventElapsedTime(&kernelMs, start, stop);

    /**
     * ДААЛГАВАР 5: Үр дүнг GPU-ээс CPU рүү буцааж хуулах
     * device_result -> host_result
     */
    // cudaMemcpy(...);
    cudaEvent_t d2h_start, d2h_end;
    cudaEventCreate(&d2h_start);
    cudaEventCreate(&d2h_end);

    cudaEventRecord(d2h_start);

    cudaMemcpy(host_result, device_result, size, cudaMemcpyDeviceToHost);

    cudaEventRecord(d2h_end);
    cudaEventSynchronize(d2h_end);
    float d2h_ms = 0;
    cudaEventElapsedTime(&d2h_ms, d2h_start, d2h_end);

    auto totalEnd = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> totalMs = totalEnd - totalStart;

    float totalTransferTime = h2d_ms + d2h_ms;

    float total_bytes = N * 3 * sizeof(float);
    float bandwidth = total_bytes / (totalTransferTime / 1000.0f) / 1e9;

    // Үр дүнг хэвлэх
    printf("--- CUDA SAXPY Result ---\n");
    printf("Total time (including memory transfer): %.3f ms\n", totalMs.count());
    printf("Kernel execution time:                 %.3f ms\n", kernelMs);
    printf("Malloc time: %.3fms\n", malloc_ms);
    printf("Transfer time: %.3fms\n", totalTransferTime);
    printf("Bandwidth: %.3f GB/s\n", bandwidth);

    // Чөлөөлөх
    cudaFree(device_x);
    cudaFree(device_y);
    cudaFree(device_result);
    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    cudaEventDestroy(h2d_start);
    cudaEventDestroy(h2d_end);
    cudaEventDestroy(d2h_start);
    cudaEventDestroy(d2h_end);
    cudaEventDestroy(malloc_start);
    cudaEventDestroy(malloc_end);
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

    for (int i = 0; i < 3; i++)
    {
        run_saxpy(N, alpha, x, y, result);
    }

    // Шалгалт (Verification)
    bool success = true;
    for (int i = 0; i < 10000; i++)
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