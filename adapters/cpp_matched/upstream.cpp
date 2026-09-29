#include <cstdint>
#include <vector>
#include GARAMON_HEADER

using Mvec = GARAMON_NAMESPACE::Mvec<double>;

struct NativeBatch {
    std::vector<Mvec> left, right;
    std::vector<std::uint64_t> output_masks;
};

extern "C" void* garamon_native_prepare(
    const double* left, const double* right,
    const std::uint64_t* left_masks, const std::uint64_t* right_masks,
    const std::uint64_t* output_masks,
    std::int64_t nleft, std::int64_t nright, std::int64_t noutput,
    std::int64_t columns) noexcept {
    NativeBatch* batch = nullptr;
    try {
        batch = new NativeBatch;
        batch->left.resize(columns);
        batch->right.resize(columns);
        batch->output_masks.assign(output_masks, output_masks+noutput);
        const std::uint64_t limit = std::uint64_t(1) << GARAMON_DIMENSION;
        for (std::int64_t i=0; i<nleft; ++i)
            if (left_masks[i] >= limit) { delete batch; return nullptr; }
        for (std::int64_t i=0; i<nright; ++i)
            if (right_masks[i] >= limit) { delete batch; return nullptr; }
        for (auto mask : batch->output_masks)
            if (mask >= limit) { delete batch; return nullptr; }
        for (std::int64_t column=0; column<columns; ++column) {
            for (std::int64_t i=0; i<nleft; ++i)
                batch->left[column][int(left_masks[i])] = left[column*nleft+i];
            for (std::int64_t i=0; i<nright; ++i)
                batch->right[column][int(right_masks[i])] = right[column*nright+i];
        }
        return batch;
    } catch (...) {
        delete batch;
        return nullptr;
    }
}

extern "C" int garamon_native_product(void* handle, double* output) noexcept {
    try {
        auto& batch = *static_cast<NativeBatch*>(handle);
        for (std::size_t column=0; column<batch.left.size(); ++column) {
            const auto value = batch.left[column] * batch.right[column];
            for (std::size_t i=0; i<batch.output_masks.size(); ++i)
                output[column*batch.output_masks.size()+i] = value[int(batch.output_masks[i])];
        }
        return 0;
    } catch (...) { return -1; }
}

extern "C" void garamon_native_destroy(void* handle) noexcept {
    delete static_cast<NativeBatch*>(handle);
}
