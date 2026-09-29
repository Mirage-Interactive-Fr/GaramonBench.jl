#include <cstddef>
#include <cstdint>

// Experimental port of Garamon.jl run_packed_batch's path loop. This is not the
// algorithm used by the upstream generated Mvec product. Inputs, validation and
// zero-initialized output allocation are shared by the Julia benchmark frontend.
struct Path {
    std::int64_t left;
    std::int64_t right;
    std::int64_t output;
    double factor;
};
static_assert(sizeof(Path) == 32, "unexpected packed path ABI");

extern "C" std::size_t garamon_path_size() { return sizeof(Path); }
extern "C" std::size_t garamon_path_offset(int field) {
    const std::size_t offsets[] = {offsetof(Path, left), offsetof(Path, right),
                                   offsetof(Path, output), offsetof(Path, factor)};
    return field >= 0 && field < 4 ? offsets[field] : sizeof(Path);
}

extern "C" void garamon_packed_product(
    const Path* paths, std::int64_t npaths,
    const double* left, const double* right, double* output,
    std::int64_t nleft, std::int64_t nright, std::int64_t noutput,
    std::int64_t columns) noexcept {
    for (std::int64_t column = 0; column < columns; ++column) {
        for (std::int64_t p = 0; p < npaths; ++p) {
            const auto& path = paths[p];
            output[column*noutput + path.output - 1] +=
                path.factor * left[column*nleft + path.left - 1] *
                right[column*nright + path.right - 1];
        }
    }
}
