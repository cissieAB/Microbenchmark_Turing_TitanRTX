//This code is a modification of L2 cache benchmark from 
//"Dissecting the NVIDIA Volta GPU Architecture via Microbenchmarking": https://arxiv.org/pdf/1804.06826.pdf

//This benchmark measures the read latency of L2 cache

//This code have been tested on Volta V100 architecture

#include <stdio.h>   
#include <stdlib.h> 
#include <cuda.h>

#define TEST_SIZE 1
#define WARP_SIZE 32
#define L1_SIZE 32768
#define THREADS_NUM 1024
#define ARRAY_SIZE (TEST_SIZE+L1_SIZE)

// GPU error check
#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true){
        if (code != cudaSuccess) {
                fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
                if (abort) exit(code);
        }
}

__global__ void l1_bw(uint32_t *startClk, uint32_t *stopClk, float *dsink, float *posArray){
	
	// thread index
	uint32_t tid = threadIdx.x;
	if(tid < TEST_SIZE){
	// a register to avoid compiler optimization
	float sink = 0;
	// populate l2 cache to warm up
	if (tid<TEST_SIZE){
		float *ptr = posArray + tid + L1_SIZE;
		asm volatile ("{\t\n"
			".reg .f32 data;\n\t"
			"ld.global.cg.f32 data, [%1];\n\t"
			"add.f32 %0, data, %0;\n\t"
			"}" : "+f"(sink) : "l"(ptr) : "memory"
		);
	}

	// synchronize all threads
	asm volatile ("bar.sync 0;");

	for (uint32_t i=tid; i<L1_SIZE; i+=THREADS_NUM){
                float *ptr = posArray + i;
                asm volatile ("{\t\n"
                        ".reg .f32 data;\n\t"
                        "ld.global.cg.f32 data, [%1];\n\t"
                        "add.f32 %0, data, %0;\n\t"
                        "}" : "+f"(sink) : "l"(ptr) : "memory"
                );
	}
	
        // synchronize all threads
        asm volatile ("bar.sync 0;");

	// start timing
	uint32_t start = 0;
	asm volatile ("mov.u32 %0, %%clock;" : "=r"(start) :: "memory");
	
	// load data from l2 cache and accumulate
	
        if (tid<TEST_SIZE){
                float *ptr = posArray + tid + L1_SIZE;
                asm volatile ("{\t\n"
                        ".reg .f32 data;\n\t"
                        "ld.global.cg.f32 data, [%1];\n\t"
                        "add.f32 %0, data, %0;\n\t"
                        "}" : "+f"(sink) : "l"(ptr) : "memory"
                );
        }

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
	float *posArray = (float*) malloc(ARRAY_SIZE*sizeof(float));
	float *dsink = (float*) malloc(THREADS_NUM*sizeof(float));
	
	uint32_t *startClk_g;
        uint32_t *stopClk_g;
        float *posArray_g;
        float *dsink_g;
	
	for (uint32_t i=0; i<ARRAY_SIZE; i++)
		posArray[i] = (float)i;
		
	gpuErrchk( cudaMalloc(&startClk_g, THREADS_NUM*sizeof(uint32_t)) );
	gpuErrchk( cudaMalloc(&stopClk_g, THREADS_NUM*sizeof(uint32_t)) );
	gpuErrchk( cudaMalloc(&posArray_g, ARRAY_SIZE*sizeof(float)) );
	gpuErrchk( cudaMalloc(&dsink_g, THREADS_NUM*sizeof(float)) );
	
	gpuErrchk( cudaMemcpy(posArray_g, posArray, ARRAY_SIZE*sizeof(float), cudaMemcpyHostToDevice) );

	l1_bw<<<1,THREADS_NUM>>>(startClk_g, stopClk_g, dsink_g, posArray_g);

	gpuErrchk( cudaMemcpy(startClk, startClk_g, THREADS_NUM*sizeof(uint32_t), cudaMemcpyDeviceToHost) );
	gpuErrchk( cudaMemcpy(stopClk, stopClk_g, THREADS_NUM*sizeof(uint32_t), cudaMemcpyDeviceToHost) );
	gpuErrchk( cudaMemcpy(dsink, dsink_g, THREADS_NUM*sizeof(float), cudaMemcpyDeviceToHost) );
	printf("L2 Latency for %d threads = %u \n", TEST_SIZE, stopClk[0]-startClk[0]);

	return 0;
} 