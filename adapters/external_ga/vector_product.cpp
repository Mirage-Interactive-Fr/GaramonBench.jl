// One comparable EGA3 vector-by-vector geometric product per library.
// Inputs are two arrays of three doubles per product. Outputs are ordered
// by blade mask: scalar, e12, e13, e23. The caller owns every buffer.
#if defined(GB_GAL)
#include <gal/vga.hpp>
#elif defined(GB_VERSOR)
#include <vsr/vsr.h>
#else
#error "Select exactly one GA library"
#endif

extern "C" void gb_vector_batch(const double* lhs, const double* rhs,
                                  double* output, int count) {
    for (int t = 0; t < count; ++t) {
        const double* a = lhs + 3 * t;
        const double* b = rhs + 3 * t;
        double* y = output + 4 * t;
#if defined(GB_GAL)
        const gal::vga::vector<double> u(a[0], a[1], a[2]);
        const gal::vga::vector<double> v(b[0], b[1], b[2]);
        const auto product = gal::vga::compute(
            [](auto x, auto z) { return x * z; }, u, v);
        y[0] = product.select(0);
        y[1] = product.select(3);
        y[2] = product.select(5);
        y[3] = product.select(6);
#elif defined(GB_VERSOR)
        const vsr::euclidean_vector<3, double> u(a[0], a[1], a[2]);
        const vsr::euclidean_vector<3, double> v(b[0], b[1], b[2]);
        const auto product = u * v;
        y[0] = product[0];
        y[1] = product[1];
        y[2] = product[2];
        y[3] = product[3];
#endif
    }
}
