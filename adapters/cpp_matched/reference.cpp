#include <cstdint>
#include <memory>
#include <vector>
#include GB_REFERENCE_HEADER

#ifdef GB_REFERENCE_INT64
using Scalar = std::int64_t;
#else
using Scalar = double;
#endif
using Mvec = GB_REFERENCE_NAMESPACE::Mvec<Scalar>;

struct Batch {
    std::vector<Mvec> operands;
    std::vector<int> output_masks;
    int arity;
    int operation;
    int width;
    bool varying_outputs;
    bool aggregate;
};

extern "C" void* gb_reference_prepare(const int* offsets, const int* masks,
                                      const Scalar* values, int count, int arity,
                                      const int* outputs, int width, int operation,
                                      int aggregate, int varying_outputs) noexcept {
    try {
        auto batch = std::make_unique<Batch>();
        batch->arity = arity;
        batch->operation = operation;
        batch->aggregate = aggregate;
        batch->width = width;
        batch->varying_outputs = varying_outputs;
        batch->output_masks.assign(outputs, outputs + width * (varying_outputs ? count : 1));
        batch->operands.resize(count * arity);
        for (int k = 0; k < count * arity; ++k) {
            for (int i = offsets[k]; i < offsets[k + 1]; ++i) {
                batch->operands[k][masks[i]] = values[i];
            }
        }
        return batch.release();
    } catch (...) {
        return nullptr;
    }
}

extern "C" void gb_reference_destroy(void* handle) noexcept {
    delete static_cast<Batch*>(handle);
}

static Mvec evaluate(const Mvec* operands, int operation, int arity) {
    const auto& a = operands[0];
    const auto& b = operands[1];
    switch (operation) {
        case 1: return a ^ b;
        case 2: return a < b;
        case 3: return a > b;
        case 4: return a*b + a*operands[2];
        default: {
            Mvec product = a * b;
            for (int i = 2; i < arity; ++i) {
                product = product * operands[i];
            }
            return product;
        }
    }
}

extern "C" int gb_reference_execute(const void* handle, Scalar* output) noexcept {
    try {
        const auto& batch = *static_cast<const Batch*>(handle);
        Mvec total;
        for (std::size_t k = 0; k < batch.operands.size(); k += batch.arity) {
            const auto value = evaluate(&batch.operands[k], batch.operation, batch.arity);
            if (batch.aggregate) {
                total += value;
            } else {
                const auto offset = batch.varying_outputs ? (k / batch.arity) * batch.width : 0;
                for (int i = 0; i < batch.width; ++i) {
                    *output++ = value[batch.output_masks[offset + i]];
                }
            }
        }
        if (batch.aggregate) {
            const auto& result = total;
            for (const int mask : batch.output_masks) {
                *output++ = result[mask];
            }
        }
        return 0;
    } catch (...) {
        return -1;
    }
}
