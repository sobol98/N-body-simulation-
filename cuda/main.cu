/*
    * File path: 
    * .../N-body-simulation/cuda
    * 
    * To compile:
    * nvcc main.cu -o main
    * 
    * To run:
    * ./main
*/


#include <stdio.h>
#include <cuda.h>
#include <math.h>
#include <cuda_runtime.h>
#include <vector_types.h>
#include <sys/time.h>
#include <cuda_runtime.h>


//---------- Constants ----------//

#define G 6.67430e-11
#define DELTA_TIME 0.1 // time step in simulation time (in seconds)
#define T_END 100000 // how many seconds (in real time) the simulation will run
#define N 10 // number of bodies

#define BLOCK_SIZE 256 // idk what this is


//---------- Structs ----------//
struct Body {
    float3 position;
    float3 velocity;
    float3 force;
    float mass;
};



//---------- Functions ----------//

__device__ float dot_product(float3 a) {
    return a.x * a.x + a.y * a.y + a.z * a.z;
}

// this function calculate initial position of the N bodies in the our empty universum
void initBodies(Body *bodies, int n) {
    float destination_parameter = 1.0e+4;
    float mass_parameter = 1.0e+24;

    for (int i = 0; i < n; i++) {
        bodies[i].position.x = ((rand() % 1000) - 500)*destination_parameter;
        bodies[i].position.y = ((rand() % 1000) - 500)*destination_parameter;
        bodies[i].position.z = ((rand() % 1000) - 500)*destination_parameter;
        
        bodies[i].velocity.x = ((rand() % 1000) - 500)*destination_parameter;
        bodies[i].velocity.y = ((rand() % 1000) - 500)*destination_parameter;
        bodies[i].velocity.z = ((rand() % 1000) - 500)*destination_parameter;
        
        bodies[i].mass = (rand() % 1000 + 1) * mass_parameter;                                       
    }
}



//CUDA kernel that calculates the gravitational forces acting on each body
__global__ void calculate_parameters(Body *bodies, int n) {
    // int i = blockIdx.x * blockDim.x + threadIdx.x;
    int i =0;
    if (i < n) {
        float3 f = make_float3(0, 0, 0);

        for (int j = 0; j < n; j++) {
            if (i != j) {
                float3 diff = make_float3(bodies[j].position.x - bodies[i].position.x,
                                        bodies[j].position.y - bodies[i].position.y,
                                        bodies[j].position.z - bodies[i].position.z);
                
                float dist = sqrtf(dot_product(diff)); //calculation of the length of the displacement vector (diagonal of 3 dimensions)
                float forceMagnitude = G * bodies[i].mass * bodies[j].mass / (dist * dist + 1e-10f);  //+ 1e-10f -> prevent division by zero
                
                f.x += forceMagnitude * diff.x / dist;
                f.y += forceMagnitude * diff.y / dist;
                f.z += forceMagnitude * diff.z / dist;
            }
        }
        bodies[i].force = f;
    }
}

//CUDA kernel that updates the positions and velocities of each body based on the forces calculated.
__global__ void updateBodies(Body *bodies, float3 *forces, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        bodies[i].velocity.x += forces[i].x / bodies[i].mass * DELTA_TIME;
        bodies[i].velocity.y += forces[i].y / bodies[i].mass * DELTA_TIME;
        bodies[i].velocity.z += forces[i].z / bodies[i].mass * DELTA_TIME;

        bodies[i].position.x += bodies[i].velocity.x * DELTA_TIME;
        bodies[i].position.y += bodies[i].velocity.y * DELTA_TIME;
        bodies[i].position.z += bodies[i].velocity.z * DELTA_TIME;
    }
}

// Initializes the bodies with random positions, velocities, and masses for (int i = 0; i < n; i++) {
    


void checkCudaError(cudaError_t error) {
    if (error != cudaSuccess) {
        fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(error));
        exit(-1);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <number of bodies>\n", argv[0]);
        exit(-1);
    }

    int n = atoi(argv[1]); // Convert command-line argument to integer
    if (n <= 0) {
        fprintf(stderr, "Number of bodies must be a positive integer\n");
        exit(-1);
    }

    // Get the number of CUDA devices
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        fprintf(stderr, "No CUDA devices available\n");
        return 1;
    }

    // Query CUDA device properties
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);                                      // Assuming using the first device
    // printf("Device Name: %s\n", prop.name);                                 //is an ASCII string identifying the device
    // printf("Number of multiprocessors: %d\n", prop.multiProcessorCount);    // is the number of multiprocessors on the device
    // printf("Total global memory: %zu bytes\n", prop.totalGlobalMem);        //is the total amount of global memory available on the device in bytes
    // printf("Maximum number of threads per block: %d bytes\n", prop.maxThreadsPerBlock);   // is the maximum number of threads per block;
    // printf("maximum size of each dimension of a block: %d bytes\n", prop.maxThreadsDim[3]);      // contains the maximum size of each dimension of a block;
    // printf("maximum size of each dimension of a grid: %d bytes\n", prop.maxGridSize[3]);        // contains the maximum size of each dimension of a grid;
    // printf("clock frequency in kilohertz: %d bytes\n", prop.clockRate);             //is the clock frequency in kilohertz;
    

    // Define CUDA events for timing
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    // Start recording
    cudaEventRecord(start);

    Body *h_bodies = (Body*)malloc(n * sizeof(Body));
    initBodies(h_bodies, n);

    Body *d_bodies;
    float3 *d_forces;
    checkCudaError(cudaMalloc(&d_bodies, n * sizeof(Body)));
    checkCudaError(cudaMalloc(&d_forces, n * sizeof(float3)));
    checkCudaError(cudaMemcpy(d_bodies, h_bodies, n * sizeof(Body), cudaMemcpyHostToDevice));

    dim3 blockSize(BLOCK_SIZE);
    dim3 gridSize((n + blockSize.x - 1) / blockSize.x);

    for (int iter = 0; iter < (Tend/DT); iter++) {
        computeForces<<<gridSize, blockSize>>>(d_bodies, d_forces, n); // Pass n as an argument
        updateBodies<<<gridSize, blockSize>>>(d_bodies, d_forces, n); // Pass n as an argument
        checkCudaError(cudaDeviceSynchronize());
    }

    // Stop recording
    cudaEventRecord(stop);
    cudaEventSynchronize(stop);

    // Calculate and print the elapsed time
    float milliseconds = 0;
    cudaEventElapsedTime(&milliseconds, start, stop);
    printf("Time taken for execution: %f milliseconds\n", milliseconds);

    // Destroy CUDA events
    cudaEventDestroy(start);
    cudaEventDestroy(stop);

    // Copy data back to host for output
    checkCudaError(cudaMemcpy(h_bodies, d_bodies, n * sizeof(Body), cudaMemcpyDeviceToHost));
    
    cudaFree(d_bodies);
    cudaFree(d_forces);
    free(h_bodies);

    return 0;
}