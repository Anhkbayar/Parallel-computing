#include <stdio.h>
#include <cuda_runtime.h>
#include <chrono>

__global__ void up_sweep(){
    int i = blockIdx.x * blockDim.x + threadIdx.x;
}

__global__ void down_sweep(){

}