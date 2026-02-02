#include <stdio.h>
#include <omp.h>

int main(int argc, char *argv[]){
    #pragma omp parallel num_threads(4)
    {
        int nthreads, thread_id;
        nthreads = omp_get_num_threads();
        thread_id = omp_get_thread_num();
        printf("Hello OpenMP\n");
        printf("I have %d thread(s) and my thread is %d\n", nthreads, thread_id);
    }
}