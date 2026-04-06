#include <iostream>
#include <vector>
#include <cuda_runtime.h>
#include <cmath>

// Exclusive scan
__global__ void up_sweep_kernel(int *d_arr, int d, int num_threads)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < num_threads)
    {
        int ai = d * (2 * i + 1) - 1;
        int bi = d * (2 * i + 2) - 1;
        d_arr[bi] += d_arr[ai];
    }
}

__global__ void down_sweep_kernel(int *d_arr, int d, int num_threads)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < num_threads)
    {
        int ai = d * (2 * i + 1) - 1;
        int bi = d * (2 * i + 2) - 1;
        int temp = d_arr[ai];
        d_arr[ai] = d_arr[bi];
        d_arr[bi] += temp;
    }
}

int nextPowerOf2(int n)
{
    n--;
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    n++;
    return n;
}

void exclusive_scan(int *d_arr, int n)
{
    int input_size_new = nextPowerOf2(n);
    int threadsPerBlock = 256;

    // upsweep
    for (int d = 1; d < input_size_new; d *= 2)
    {
        int num_threads = input_size_new / (2 * d);
        int blocks = (num_threads + threadsPerBlock - 1) / threadsPerBlock;
        if (blocks > 0)
        {
            up_sweep_kernel<<<blocks, threadsPerBlock>>>(d_arr, d, num_threads);
            cudaDeviceSynchronize();
        }
    }

    // root zero
    int zero = 0;
    cudaMemcpy(&d_arr[input_size_new - 1], &zero, sizeof(int), cudaMemcpyHostToDevice);

    // downsweep
    for (int d = input_size_new / 2; d > 0; d /= 2)
    {
        int num_threads = input_size_new / (2 * d);
        int blocks = (num_threads + threadsPerBlock - 1) / threadsPerBlock;
        if (blocks > 0)
        {
            down_sweep_kernel<<<blocks, threadsPerBlock>>>(d_arr, d, num_threads);
            cudaDeviceSynchronize();
        }
    }
}
// Find repeats
__global__ void mark_repeat_kernel(const int *d_in, int *d_flag, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n - 1)
    {
        bool matchLeft = (i > 0 && d_in[i] == d_in[i - 1]);
        bool matchRight = (i < n - 1 && d_in[i] == d_in[i + 1]);
        if (matchLeft || matchRight)
        {
            d_flag[i] = 1;
        }
        else
        {
            d_flag[i] = 0;
        }
    }
}

__global__ void scatter_flag_kernel(const int *d_flag, const int *d_scan, int *d_out, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n - 1)
    {
        if (d_flag[i] == 1)
        {
            int target_idx = d_scan[i];
            d_out[target_idx] = i;
        }
    }
}

int find_repeats(const std::vector<int> &h_in, std::vector<int> &h_out)
{
    int input_size = (int)h_in.size();
    int input_new_size = nextPowerOf2(input_size);

    int threadsPerBlock = 256;
    int blocks = (input_size + threadsPerBlock - 1) / threadsPerBlock;

    int *d_in, *d_flags, *d_scan, *d_out_indices;
    cudaMalloc(&d_in, input_size * sizeof(int));
    cudaMalloc(&d_flags, input_new_size * sizeof(int));
    cudaMalloc(&d_scan, input_new_size * sizeof(int));
    cudaMalloc(&d_out_indices, input_size * sizeof(int));

    cudaMemset(d_flags, 0, input_new_size * sizeof(int));
    cudaMemcpy(d_in, h_in.data(), input_size * sizeof(int), cudaMemcpyHostToDevice);

    // Mark repeat
    mark_repeat_kernel<<<blocks, threadsPerBlock>>>(d_in, d_flags, input_size);
    cudaDeviceSynchronize();

    // Exclusive scan on flags
    cudaMemcpy(d_scan, d_flags, input_new_size * sizeof(int), cudaMemcpyDeviceToDevice);
    exclusive_scan(d_scan, input_size);

    int last_flag, last_scan_val;
    cudaMemcpy(&last_flag, &d_flags[input_size - 1], sizeof(int), cudaMemcpyDeviceToHost);
    cudaMemcpy(&last_scan_val, &d_scan[input_size - 1], sizeof(int), cudaMemcpyDeviceToHost);
    int total_repeats = last_scan_val + last_flag;

    // scatter
    scatter_flag_kernel<<<blocks, threadsPerBlock>>>(d_flags, d_scan, d_out_indices, input_size);
    cudaDeviceSynchronize();

    h_out.resize(total_repeats);
    if (total_repeats > 0)
    {
        cudaMemcpy(h_out.data(), d_out_indices, total_repeats * sizeof(int), cudaMemcpyDeviceToHost);
    }

    cudaFree(d_in);
    cudaFree(d_flags);
    cudaFree(d_scan);
    cudaFree(d_out_indices);

    return total_repeats;
}

int main()
{
    std::vector<int> h_in = {5, 8, 3, 1, 1, 1, 1, 3, 6, 2, 2, 2, 3, 5, 7, 4};
    std::vector<int> h_out;
    
    std::cout << "--- Find repeats test ---\n";
    std::cout << "Input: ";
    for (int nums : h_in)
        std::cout << nums << " ";
    std::cout << "\n";

    int repeat_count = find_repeats(h_in, h_out);

    std::cout << "Found " << repeat_count << " repeat at indices: ";
    for (int i : h_out)
        std::cout << i << " ";
    std::cout << std::endl;

    return 0;
}