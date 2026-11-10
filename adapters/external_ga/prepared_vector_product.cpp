// EGA3 vector-by-vector products, in mask order 0, 3, 5, 6.
#include <memory>
#include <vector>

#ifdef GB_FLOAT32
using Scalar = float;
#else
using Scalar = double;
#endif

#if defined(GB_GAL)
#include <gal/vga.hpp>
using Vector = gal::vga::vector<Scalar>;
#elif defined(GB_VERSOR)
#include <vsr/vsr.h>
using Vector = vsr::euclidean_vector<3, Scalar>;
#elif defined(GB_KLEIN)
#include <klein/klein.hpp>
using Vector = kln::plane;
#elif defined(GB_GARAMON_CPP)
#include <e3ga/Mvec.hpp>
using Vector = e3ga::Mvec<Scalar>;
#else
#error "Select exactly one GA library"
#endif

static Vector make_vector(const Scalar* coordinates) {
#if defined(GB_KLEIN)
    return Vector(coordinates[0], coordinates[1], coordinates[2], 0.0f);
#elif defined(GB_GARAMON_CPP)
    Vector value;
    value[1] = coordinates[0];
    value[2] = coordinates[1];
    value[4] = coordinates[2];
    return value;
#else
    return Vector(coordinates[0], coordinates[1], coordinates[2]);
#endif
}

struct Batch {
    std::vector<Vector> left, right;
};

extern "C" void* gb_vector_prepare(const Scalar* left, const Scalar* right,
                                   int count) noexcept {
    try {
        auto batch = std::make_unique<Batch>();
        batch->left.reserve(count);
        batch->right.reserve(count);
        for (int t = 0; t < count; ++t) {
            batch->left.push_back(make_vector(left + 3 * t));
            batch->right.push_back(make_vector(right + 3 * t));
        }
        return batch.release();
    } catch (...) {
        return nullptr;
    }
}

extern "C" void gb_vector_destroy(void* handle) noexcept {
    delete static_cast<Batch*>(handle);
}

extern "C" int gb_vector_product(const void* handle, Scalar* output) noexcept {
    try {
        const auto& batch = *static_cast<const Batch*>(handle);
        for (std::size_t t = 0; t < batch.left.size(); ++t) {
            const auto& u = batch.left[t];
            const auto& v = batch.right[t];
            Scalar* y = output + 4 * t;
#if defined(GB_GAL)
            const auto product = gal::vga::compute(
                [](auto x, auto z) { return x * z; }, u, v);
            y[0] = product.select(0);
            y[1] = product.select(3);
            y[2] = product.select(5);
            y[3] = product.select(6);
#elif defined(GB_KLEIN)
            const auto product = u * v;
            y[0] = product.scalar();
            y[1] = product.e12();
            y[2] = -product.e31();
            y[3] = product.e23();
#elif defined(GB_GARAMON_CPP)
            const auto product = u * v;
            y[0] = product[0];
            y[1] = product[3];
            y[2] = product[5];
            y[3] = product[6];
#else
            const auto product = u * v;
            y[0] = product[0];
            y[1] = product[1];
            y[2] = product[2];
            y[3] = product[3];
#endif
        }
        return 0;
    } catch (...) {
        return -1;
    }
}
