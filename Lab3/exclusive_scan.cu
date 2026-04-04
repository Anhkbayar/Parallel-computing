#include <iostream>
#include <vector>
#include <cuda_runtime.h>
#include <cmath>

// Алдаа шалгах макро
#define CUDA_CHECK(call) \
    do { \
        cudaError_t err = call; \
        if (err != cudaSuccess) { \
            std::cerr << "CUDA Error: " << cudaGetErrorString(err) << " at line " << __LINE__ << std::endl; \
            exit(1); \
        } \
    } while(0)

// Хамгийн ойрын 2-ын зэрэгтийг олох функц
int nextPowerOf2(int n) {
    n--;
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    n++;
    return n;
}

// ---------------------------------------------------------
// 1. Up-sweep Kernel
// Зөвхөн хэрэгцээтэй thread-үүд ажиллана. if(k % d == 0) гэж шүүхгүй!
// ---------------------------------------------------------
__global__ void up_sweep_kernel(int* d_arr, int d, int num_threads) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (tid < num_threads) {
        // tid-г ашиглан массивын индексүүдийг шууд тооцоолох
        int ai = d * (2 * tid + 1) - 1;
        int bi = d * (2 * tid + 2) - 1;
        
        d_arr[bi] += d_arr[ai];
    }
}

// ---------------------------------------------------------
// 2. Down-sweep Kernel
// Дээрээс доош swap хийж нэмнэ.
// ---------------------------------------------------------
__global__ void down_sweep_kernel(int* d_arr, int d, int num_threads) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (tid < num_threads) {
        int ai = d * (2 * tid + 1) - 1;
        int bi = d * (2 * tid + 2) - 1;
        
        int temp = d_arr[ai];
        d_arr[ai] = d_arr[bi];
        d_arr[bi] += temp;
    }
}

// ---------------------------------------------------------
// 3. Host Function: Exclusive Scan
// ---------------------------------------------------------
void exclusive_scan(const std::vector<int>& h_in, std::vector<int>& h_out) {
    int n = h_in.size();
    int m = nextPowerOf2(n); // Padding хийх хэмжээ
    
    int* d_arr;
    CUDA_CHECK(cudaMalloc((void**)&d_arr, m * sizeof(int)));
    
    // Анхны утгуудыг хуулах (Мөн үлдсэн хэсгийг 0-ээр дүүргэх)
    CUDA_CHECK(cudaMemset(d_arr, 0, m * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_arr, h_in.data(), n * sizeof(int), cudaMemcpyHostToDevice));
    
    int threadsPerBlock = 256;
    
    // --- Үе 1: Up-sweep (Reduce) ---
    for (int d = 1; d < m; d *= 2) {
        int num_threads = m / (2 * d); // Яг хэрэгтэй thread-ийн тоо
        int blocks = (num_threads + threadsPerBlock - 1) / threadsPerBlock;
        
        if (blocks > 0) {
            up_sweep_kernel<<<blocks, threadsPerBlock>>>(d_arr, d, num_threads);
            CUDA_CHECK(cudaDeviceSynchronize());
        }
    }
    
    // --- Үе 2: Үндсийг (root) 0 болгох ---
    // Down-sweep эхлэхийн өмнө массивын хамгийн сүүлийн элементийг 0 болгоно.
    int zero = 0;
    CUDA_CHECK(cudaMemcpy(&d_arr[m - 1], &zero, sizeof(int), cudaMemcpyHostToDevice));
    
    // --- Үе 3: Down-sweep ---
    for (int d = m / 2; d > 0; d /= 2) {
        int num_threads = m / (2 * d);
        int blocks = (num_threads + threadsPerBlock - 1) / threadsPerBlock;
        
        if (blocks > 0) {
            down_sweep_kernel<<<blocks, threadsPerBlock>>>(d_arr, d, num_threads);
            CUDA_CHECK(cudaDeviceSynchronize());
        }
    }
    
    // Үр дүнг буцааж Host руу авах (Зөвхөн анхны N элементийг авна)
    h_out.resize(n);
    CUDA_CHECK(cudaMemcpy(h_out.data(), d_arr, n * sizeof(int), cudaMemcpyDeviceToHost));
    
    CUDA_CHECK(cudaFree(d_arr));
}

// ---------------------------------------------------------
// Тестлэх хэсэг
// ---------------------------------------------------------
int main() {
    // N нь 2-ын зэрэгт биш (жишээ нь 11)
    std::vector<int> h_in = {3, 1, 7, 0, 4, 1, 6, 3, 2, 5, 8};
    std::vector<int> h_out;
    
    std::cout << "(Input):\n";
    for(int val : h_in) std::cout << val << " ";
    std::cout << "\n";
    
    exclusive_scan(h_in, h_out);
    
    std::cout << "Exclusive scan:\n";
    for(int val : h_out) std::cout << val << " ";
    std::cout << "\n";
    
    return 0;
}