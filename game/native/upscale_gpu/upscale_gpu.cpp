#include <gpu.h>
#include <net.h>

#include <cstddef>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr int layers = 34;
constexpr int features = 64;
constexpr int output_channels = 48;
constexpr size_t weight_bytes = 32 + 1213296 * 2;

struct Network {
    // ncnn's in-memory reader can keep views into the model.
    std::vector<float> model;
    ncnn::Net net;
};

bool load_model(Network& network, const unsigned char* weights) {
    std::string graph = "7767517\n68 68\nInput input 0 1 input\n";
    std::string previous = "input";
    auto& model = network.model;
    model.reserve(1213296 + layers);
    const unsigned char* data = weights + 32;
    const auto read_floats = [&](int count) {
        for (int i = 0; i < count; ++i, data += 2) {
            unsigned short half = static_cast<unsigned short>(data[0] | (data[1] << 8));
            model.push_back(ncnn::float16_to_float32(half));
        }
    };

    for (int i = 0; i < layers; ++i) {
        int inputs = i == 0 ? 3 : features;
        int outputs = i == layers - 1 ? output_channels : features;
        int count = inputs * outputs * 9;
        std::string name = "conv" + std::to_string(i);
        graph += "Convolution " + name + " 1 1 " + previous + " " + name
            + " 0=" + std::to_string(outputs) + " 1=3 4=1 5=1 6=" + std::to_string(count) + "\n";
        model.push_back(0.f); // ncnn's 32-bit convolution weight format.
        read_floats(count + outputs);
        previous = name;
        if (i < layers - 1) {
            name = "prelu" + std::to_string(i);
            graph += "PReLU " + name + " 1 1 " + previous + " " + name + " 0=64\n";
            read_floats(features);
            previous = name;
        }
    }
    return data == weights + weight_bytes
        && network.net.load_param_mem(graph.c_str()) == 0
        && network.net.load_model(reinterpret_cast<const unsigned char*>(model.data())) == model.size() * sizeof(float);
}
}

extern "C" __declspec(dllexport) void* el_upscale_gpu_create(const unsigned char* weights, size_t size) {
    if (size != weight_bytes || std::memcmp(weights, "ELSR", 4) != 0 || ncnn::get_gpu_count() < 1) return nullptr;
    try {
        auto network = std::make_unique<Network>();
        network->net.set_vulkan_device(ncnn::get_default_gpu_index());
        network->net.opt.use_vulkan_compute = true;
        network->net.opt.use_fp16_storage = true;
        network->net.opt.use_fp16_arithmetic = true;
        return load_model(*network, weights) ? network.release() : nullptr;
    } catch (...) {
        return nullptr;
    }
}

extern "C" __declspec(dllexport) void el_upscale_gpu_destroy(void* context) {
    delete static_cast<Network*>(context);
    ncnn::destroy_gpu_instance();
}

extern "C" __declspec(dllexport) int el_upscale_gpu_tile(
    void* context, const float* rgb, int pitch, int width, int height, float* output) {
    try {
        ncnn::Mat input(width, height, 3);
        if (input.empty()) return 0;
        for (int channel = 0; channel < 3; ++channel) {
            float* plane = input.channel(channel);
            for (int y = 0; y < height; ++y)
                for (int x = 0; x < width; ++x)
                    plane[y * width + x] = rgb[(y * pitch + x) * 3 + channel];
        }

        ncnn::Extractor extractor = static_cast<Network*>(context)->net.create_extractor();
        ncnn::Mat features_out;
        if (extractor.input("input", input) || extractor.extract("conv33", features_out)
            || features_out.w != width || features_out.h != height || features_out.c != output_channels
            || features_out.elembits() != 32 || features_out.elempack != 1) return 0;
        for (int channel = 0; channel < output_channels; ++channel) {
            const float* plane = features_out.channel(channel);
            for (int p = 0; p < width * height; ++p)
                output[p * output_channels + channel] = plane[p];
        }
        return 1;
    } catch (...) {
        return 0;
    }
}
