#include <stdio.h>
#include <cuda_runtime.h>
#include <chrono>

__global__ void my_kernel(int N, float A, float *x, float *y, float *r)
{
    int i = blockDim.x * blockIdx.x + threadIdx.x;

    if (i < N)
    {
        r[i] = A * x[i] * y[i];
    }
}

int main()
{

    // 2.Cpu memory
    int N = 1 << 10;
    float A = 2.0f;
    size_t size = N * sizeof(float);
    float *h_x = (float *)malloc(size);
    float *h_y = (float *)malloc(size);
    float *h_r = (float *)malloc(size);

    for (int i = 0; i < N; i++)
    {
        h_x[i] = 1.0;
        h_y[i] = 2.0;
    }

    // 3.gpu memory
    float *d_x, *d_y, *d_r;
    cudaMalloc(&d_x, size);
    cudaMalloc(&d_y, size);
    cudaMalloc(&d_r, size);

    // 4. host to device
    cudaMemcpy(d_x, h_x, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_y, h_y, size, cudaMemcpyHostToDevice);

    // 5. Kernel run
    int threads = 256;
    int blocks = (N + threads - 1) / threads;

    my_kernel<<<blocks, threads>>>(N, A, d_x, d_y, d_r);

    // 6. device to host
    cudaMemcpy(h_r, d_r, size, cudaMemcpyDeviceToHost);

    bool bl = true;
    for (int i = 0; i < N; i++)
    {
        if (h_r[i] != 4.0)
        {
            bl = false;
            break;
        }
    }

    if (h_r[0] == 4.0f)
    {
        printf("OK");
    }
    else
    {
        printf("Problem");
    }

    return 0;
}