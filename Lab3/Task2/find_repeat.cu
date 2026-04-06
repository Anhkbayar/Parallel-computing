#include <iostream>
#include <vector>
#include <cuda_runtime.h>
#include <cmath>

// ─────────────────────────────────────────────
// Алдаа шалгах макро
// ─────────────────────────────────────────────
#define CUDA_CHECK(call)                                           \
    do                                                             \
    {                                                              \
        cudaError_t err = call;                                    \
        if (err != cudaSuccess)                                    \
        {                                                          \
            std::cerr << "CUDA Error: " << cudaGetErrorString(err) \
                      << " at line " << __LINE__ << std::endl;     \
            exit(1);                                               \
        }                                                          \
    } while (0)

// ─────────────────────────────────────────────
// Туслах: хамгийн ойрын 2-ын зэрэгтийг олох
// ─────────────────────────────────────────────
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

// Exlusive scane
//  1. Up-sweep
__global__ void up_sweep_kernel(int *d_arr, int d, int num_threads)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < num_threads)
    {
        int ai = d * (2 * tid + 1) - 1;
        int bi = d * (2 * tid + 2) - 1;
        d_arr[bi] += d_arr[ai];
    }
}

// 2. Down-sweep давхарга
__global__ void down_sweep_kernel(int *d_arr, int d, int num_threads)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < num_threads)
    {
        int ai = d * (2 * tid + 1) - 1;
        int bi = d * (2 * tid + 2) - 1;
        int temp = d_arr[ai];
        d_arr[ai] = d_arr[bi];
        d_arr[bi] += temp;
    }
}

// ─────────────────────────────────────────────
// Host функц: Exclusive Scan
//   h_in  → оролтын вектор (Host)
//   h_out ← гаралтын вектор (Host)
void exclusive_scan(const std::vector<int> &h_in, std::vector<int> &h_out)
{
    int n = (int)h_in.size();
    int m = nextPowerOf2(n);

    int *d_arr;
    CUDA_CHECK(cudaMalloc((void **)&d_arr, m * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_arr, 0, m * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_arr, h_in.data(), n * sizeof(int), cudaMemcpyHostToDevice));

    const int TPB = 256; // threadsPerBlock

    // --- Үе 1: Up-sweep ---
    for (int d = 1; d < m; d *= 2)
    {
        int nt = m / (2 * d);
        int blocks = (nt + TPB - 1) / TPB;
        if (blocks > 0)
        {
            up_sweep_kernel<<<blocks, TPB>>>(d_arr, d, nt);
            CUDA_CHECK(cudaDeviceSynchronize());
        }
    }

    // --- Үе 2: Үндсийг 0 болгох ---
    int zero = 0;
    CUDA_CHECK(cudaMemcpy(&d_arr[m - 1], &zero, sizeof(int), cudaMemcpyHostToDevice));

    // --- Үе 3: Down-sweep ---
    for (int d = m / 2; d > 0; d /= 2)
    {
        int nt = m / (2 * d);
        int blocks = (nt + TPB - 1) / TPB;
        if (blocks > 0)
        {
            down_sweep_kernel<<<blocks, TPB>>>(d_arr, d, nt);
            CUDA_CHECK(cudaDeviceSynchronize());
        }
    }

    h_out.resize(n);
    CUDA_CHECK(cudaMemcpy(h_out.data(), d_arr, n * sizeof(int), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaFree(d_arr));
}

// Exclusive Scan – зөвхөн Device pointer авдаг
// хувилбар (find_repeats дотроос дуудна)
void exclusive_scan_device(int *d_in, int *d_out, int n)
{
    int m = nextPowerOf2(n);

    // d_out-г тусдаа m-хэмжээтэй буфер болгон ашиглана
    int *d_buf;
    CUDA_CHECK(cudaMalloc((void **)&d_buf, m * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_buf, 0, m * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_buf, d_in, n * sizeof(int), cudaMemcpyDeviceToDevice));

    const int TPB = 256;

    // Up-sweep
    for (int d = 1; d < m; d *= 2)
    {
        int nt = m / (2 * d);
        int blocks = (nt + TPB - 1) / TPB;
        if (blocks > 0)
        {
            up_sweep_kernel<<<blocks, TPB>>>(d_buf, d, nt);
            CUDA_CHECK(cudaDeviceSynchronize());
        }
    }

    // Үндсийг 0 болгох
    int zero = 0;
    CUDA_CHECK(cudaMemcpy(&d_buf[m - 1], &zero, sizeof(int), cudaMemcpyHostToDevice));

    // Down-sweep
    for (int d = m / 2; d > 0; d /= 2)
    {
        int nt = m / (2 * d);
        int blocks = (nt + TPB - 1) / TPB;
        if (blocks > 0)
        {
            down_sweep_kernel<<<blocks, TPB>>>(d_buf, d, nt);
            CUDA_CHECK(cudaDeviceSynchronize());
        }
    }

    // Зөвхөн анхны n элементийг d_out руу хуулна
    CUDA_CHECK(cudaMemcpy(d_out, d_buf, n * sizeof(int), cudaMemcpyDeviceToDevice));
    CUDA_CHECK(cudaFree(d_buf));
}

// ═════════════════════════════════════════════
//  FIND REPEATS  –  Kernel-үүд
// ═════════════════════════════════════════════

// ─────────────────────────────────────────────
// Kernel 1: Flag массив үүсгэх
//   A[i] == A[i+1]  →  F[i] = 1
//   A[i] != A[i+1]  →  F[i] = 0
//   (n-1 thread ажиллана, сүүлийн элемент харьцуулагддаггүй)
// ─────────────────────────────────────────────
__global__ void flag_kernel(const int *d_A, int *d_F, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n - 1)
    {
        d_F[i] = (d_A[i] == d_A[i + 1]) ? 1 : 0;
    }
    // Хамгийн сүүлийн байрлалд хөрш байхгүй тул 0
    if (i == n - 1)
        d_F[i] = 0;
}

// ─────────────────────────────────────────────
// Kernel 2: Үр дүнгийн массивыг дүүргэх
//   F[i] == 1  →  Output[ S[i] ] = i
// ─────────────────────────────────────────────
__global__ void scatter_kernel(const int *d_F, const int *d_S,
                               int *d_Output, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n && d_F[i] == 1)
    {
        d_Output[d_S[i]] = i;
    }
}

// ═════════════════════════════════════════════
//  find_repeats  –  Host функц
//
//  Оролт:
//    d_input  – Device дээрх массивын заагч
//    length   – массивын урт
//    d_output – Device дээрх гаралтын заагч
//               (гаднаас cudaMalloc хийгдсэн байх ёстой)
//  Гаралт:
//    return   – олдсон давтагдлын нийт тоо
// ═════════════════════════════════════════════
int find_repeats(int *d_input, int length, int *d_output)
{
    const int TPB = 256;
    int blocks = (length + TPB - 1) / TPB;

    // ── Алхам 1: F массив үүсгэх ──────────────
    int *d_F;
    CUDA_CHECK(cudaMalloc((void **)&d_F, length * sizeof(int)));
    flag_kernel<<<blocks, TPB>>>(d_input, d_F, length);
    CUDA_CHECK(cudaDeviceSynchronize());

    // ── Алхам 2: S = exclusive_scan(F) ────────
    int *d_S;
    CUDA_CHECK(cudaMalloc((void **)&d_S, length * sizeof(int)));
    exclusive_scan_device(d_F, d_S, length);

    // ── Алхам 3: Нийт давтагдлын тоог тодорхойлох ──
    //   size = F[length-1] + S[length-1]
    //   (Exclusive scan-ийн шинж чанараас)
    int last_F, last_S;
    CUDA_CHECK(cudaMemcpy(&last_F, &d_F[length - 1],
                          sizeof(int), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(&last_S, &d_S[length - 1],
                          sizeof(int), cudaMemcpyDeviceToHost));
    int total = last_F + last_S;

    // ── Алхам 4: Output-г тараах (scatter) ────
    if (total > 0)
    {
        scatter_kernel<<<blocks, TPB>>>(d_F, d_S, d_output, length);
        CUDA_CHECK(cudaDeviceSynchronize());
    }

    CUDA_CHECK(cudaFree(d_F));
    CUDA_CHECK(cudaFree(d_S));

    return total;
}

// ═════════════════════════════════════════════
//  main – тест
// ═════════════════════════════════════════════
int main()
{
    // ── Exclusive scan тест ────────────────────
    {
        std::vector<int> h_in = {3, 1, 7, 0, 4, 1, 6, 3, 2, 5, 8};
        std::vector<int> h_out;

        std::cout << "=== Exclusive Scan Test ===\n";
        std::cout << "Input : ";
        for (int v : h_in)
            std::cout << v << " ";
        std::cout << "\n";

        exclusive_scan(h_in, h_out);

        std::cout << "Output: ";
        for (int v : h_out)
            std::cout << v << " ";
        std::cout << "\n\n";
    }

    // ── Find repeats тест ─────────────────────
    {
        // Давтагдсан хөрш элементүүд: idx 1(1,1), 3(2,2), 6(5,5)
        std::vector<int> h_in = {3, 1, 1, 2, 2, 8, 5, 5, 7};
        int n = (int)h_in.size();

        std::cout << "=== Find Repeats Test ===\n";
        std::cout << "Input : ";
        for (int v : h_in)
            std::cout << v << " ";
        std::cout << "\n";
        std::cout << "Expect: indices where A[i]==A[i+1] → 1, 3, 6\n";

        // Device руу оролт хуулах
        int *d_input;
        CUDA_CHECK(cudaMalloc((void **)&d_input, n * sizeof(int)));
        CUDA_CHECK(cudaMemcpy(d_input, h_in.data(),
                              n * sizeof(int), cudaMemcpyHostToDevice));

        // Хамгийн их боломжит давтагдлын тоо = n-1
        int *d_output;
        CUDA_CHECK(cudaMalloc((void **)&d_output, (n - 1) * sizeof(int)));
        CUDA_CHECK(cudaMemset(d_output, 0, (n - 1) * sizeof(int)));

        int size = find_repeats(d_input, n, d_output);

        // Үр дүнг Host руу авах
        std::vector<int> h_result(size);
        CUDA_CHECK(cudaMemcpy(h_result.data(), d_output,
                              size * sizeof(int), cudaMemcpyDeviceToHost));

        std::cout << "Found : " << size << " repeat(s)\n";
        std::cout << "Indices: ";
        for (int v : h_result)
            std::cout << v << " ";
        std::cout << "\n";

        CUDA_CHECK(cudaFree(d_input));
        CUDA_CHECK(cudaFree(d_output));
    }

    return 0;
}
