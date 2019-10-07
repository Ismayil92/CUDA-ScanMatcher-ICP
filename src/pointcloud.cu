#pragma once
#include "pointcloud.h"
#include <cuda.h>

#define blockSize 128
#define checkCUDAErrorWithLine(msg) checkCUDAError(msg, __LINE__)

/**
* Copy the Pointcloud Positions into the VBO so that they can be drawn by OpenGL.
*/
__global__ void kernCopyPositionsToVBO(int N, glm::vec3 *pos, float *vbo, float s_scale, int vbo_offset) {
  int index = threadIdx.x + (blockIdx.x * blockDim.x);

  float c_scale = -1.0f / s_scale;

  if (index < N) {
	index += vbo_offset;
	vbo[4 * index + 0] = pos[index].x * c_scale;
    vbo[4 * index + 1] = pos[index].y * c_scale;
    vbo[4 * index + 2] = pos[index].z * c_scale;
    vbo[4 * index + 3] = 1.0f;
  }
}

/**
* Copy the Pointcloud RGB's into the VBO so that they can be drawn by OpenGL.
*/
__global__ void kernCopyRGBToVBO(int N, glm::vec3 *rgb, float *vbo, float s_scale, int vbo_offset) {
  int index = threadIdx.x + (blockIdx.x * blockDim.x);

  if (index < N) {
	index += vbo_offset;
    vbo[4 * index + 0] = rgb[index].x + 0.3f;
    vbo[4 * index + 1] = rgb[index].y + 0.3f;
    vbo[4 * index + 2] = rgb[index].z + 0.3f;
    vbo[4 * index + 3] = 1.0f;
  }
}

pointcloud::pointcloud(): isTarget(false), N(500){
	dev_pos = new glm::vec3[500];
	dev_rgb = new glm::vec3[500];
}

pointcloud::pointcloud(bool target, int numPoints): isTarget(target), N(numPoints){
	dev_pos = new glm::vec3[N];
	dev_rgb = new glm::vec3[N];
}


/******************
* CPU Methods *
******************/

/**
 * Initialize and fills dev_pos and dev_rgb array in CPU
*/
void pointcloud::initCPU() {
	buildSinusoidCPU();
}

/**
 * Populates dev_pos with a 3D Sinusoid (with or without Noise) on the CPU
*/
void pointcloud::buildSinusoidCPU() {
	float y_interval = 2.5 * PI / N;
	for (int idx = 0; idx < N; idx++) {
		dev_pos[idx] = glm::vec3(0.5f, idx*y_interval, sin(idx*y_interval));
		dev_rgb[idx] = glm::vec3(0.1f, 0.8f, 0.5f);
	}
}

/**
 * Copies dev_pos and dev_rgb into the VBO in the CPU implementation
 * This assumes that dev_pos is already filled but is on CPU
 * REALLY WACK WAY TO DO IT
*/
void pointcloud::pointCloudToVBOCPU(float *vbodptr_positions, float *vbodptr_rgb, float s_scale) {
	glm::vec3* tempPos;
	glm::vec3 * tempRGB;
	int vbo_offset = 0.0;

	//Malloc Temporary Buffers
	cudaMalloc((void**)&tempPos, N * sizeof(glm::vec3));
	cudaMalloc((void**)&tempRGB, N * sizeof(glm::vec3));
	utilityCore::checkCUDAErrorWithLine("cudaMalloc Pointcloud failed!");

	//Memcpy dev_pos and dev_rgb into temporary buffers
	cudaMemcpy(tempPos, dev_pos, N * sizeof(glm::vec3), cudaMemcpyHostToDevice);
	cudaMemcpy(tempRGB, dev_rgb, N * sizeof(glm::vec3), cudaMemcpyHostToDevice);
	utilityCore::checkCUDAErrorWithLine("cudaMemcpy Pointcloud failed!");

	//Launching Kernels
	dim3 fullBlocksPerGrid((N + blockSize - 1) / blockSize);
	kernCopyPositionsToVBO << <fullBlocksPerGrid, blockSize >> >(N, tempPos, vbodptr_positions, s_scale, vbo_offset);
	kernCopyRGBToVBO << <fullBlocksPerGrid, blockSize >> >(N, tempRGB, vbodptr_rgb, s_scale, vbo_offset);
	utilityCore::checkCUDAErrorWithLine("copyPointCloudToVBO failed!");
	cudaDeviceSynchronize();

	//Now Flipping original pointer to device so we don't crash on termination
	dev_pos = tempPos;
	dev_rgb = tempRGB;
}

pointcloud::~pointcloud() {
	cudaFree(dev_pos);
	cudaFree(dev_rgb);
}
