//This code is a modification of L1 cache benchmark from 
//"Dissecting the NVIDIA Volta GPU Architecture via Microbenchmarking": https://arxiv.org/pdf/1804.06826.pdf

//This benchmark measures the maximum read bandwidth of L1 cache

//This code have been tested on Volta V100 architecture

#include <stdio.h>   
#include <stdlib.h> 
#include <cuda.h>

#define THREADS_NUM 7
#define WARP_SIZE 32
#define L1_SIZE 16384

// GPU error check
#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true){
        if (code != cudaSuccess) {
                fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
                if (abort) exit(code);
        }
}

__global__ void l1_bw(uint32_t *startClk, uint32_t *stopClk, double *dsink, double *posArray){
	
	// thread index
	uint32_t tid = threadIdx.x;
	if(tid < THREADS_NUM){
	// a register to avoid compiler optimization
	double sink = 0;
	double *ptr = posArray + tid;
	// populate l1 cache to warm up
	asm volatile ("{\t\n"
		".reg .f64 data;\n\t"
		"ld.global.ca.f64 data, [%1];\n\t"
		"add.f64 %0, data, %0;\n\t"
		"}" : "+d"(sink) : "l"(ptr) : "memory"
	);
	
	// synchronize all threads
	asm volatile ("bar.sync 0;");
	
	// start timing
	uint32_t start = 0;
	asm volatile ("mov.u32 %0, %%clock;" : "=r"(start) :: "memory");
	
	// load data from l1 cache and accumulate
	asm volatile ("{\t\n"
		".reg .f64 data;\n\t"
		"ld.global.ca.f64 data, [%1];\n\t"
		"add.f64 %0, data, %0;\n\t"
		"}" : "+d"(sink) : "l"(ptr) : "memory"
	);

	// synchronize all threads
	asm volatile("bar.sync 0;");
	
	// stop timing
	uint32_t stop = 0;
	asm volatile("mov.u32 %0, %%clock;" : "=r"(stop) :: "memory");
	// write time and data back to memory
	startClk[tid] = start;
	stopClk[tid] = stop;
	dsink[tid] = sink;
	}
}

int main(){
	uint32_t *startClk = (uint32_t*) malloc(THREADS_NUM*sizeof(uint32_t));
	uint32_t *stopClk = (uint32_t*) malloc(THREADS_NUM*sizeof(uint32_t));
	double *posArray = (double*) malloc(THREADS_NUM*sizeof(double));
	double *dsink = (double*) malloc(THREADS_NUM*sizeof(double));
	
	uint32_t *startClk_g;
        uint32_t *stopClk_g;
        double *posArray_g;
        double *dsink_g;
	
	for (uint32_t i=0; i<THREADS_NUM; i++)
		posArray[i] = (double)i;
		
	gpuErrchk( cudaMalloc(&startClk_g, THREADS_NUM*sizeof(uint32_t)) );
	gpuErrchk( cudaMalloc(&stopClk_g, THREADS_NUM*sizeof(uint32_t)) );
	gpuErrchk( cudaMalloc(&posArray_g, THREADS_NUM*sizeof(double)) );
	gpuErrchk( cudaMalloc(&dsink_g, THREADS_NUM*sizeof(double)) );
	
	gpuErrchk( cudaMemcpy(posArray_g, posArray, THREADS_NUM*sizeof(double), cudaMemcpyHostToDevice) );
	l1_bw<<<1,THREADS_NUM>>>(startClk_g, stopClk_g, dsink_g, posArray_g);
	gpuErrchk( cudaMemcpy(startClk, startClk_g, THREADS_NUM*sizeof(uint32_t), cudaMemcpyDeviceToHost) );
	gpuErrchk( cudaMemcpy(stopClk, stopClk_g, THREADS_NUM*sizeof(uint32_t), cudaMemcpyDeviceToHost) );
	gpuErrchk( cudaMemcpy(dsink, dsink_g, THREADS_NUM*sizeof(double), cudaMemcpyDeviceToHost) );
	printf("Latency for %d threads = %u \n", THREADS_NUM, stopClk-startClk);

	return 0;
} 
