cmake_minimum_required(VERSION 3.20)
project(el_upscale_gpu LANGUAGES CXX)

find_package(ncnn 1.0.20261020 CONFIG REQUIRED)
add_library(el_upscale_gpu SHARED upscale_gpu.cpp)
target_compile_features(el_upscale_gpu PRIVATE cxx_std_17)
target_link_libraries(el_upscale_gpu PRIVATE ncnn)
