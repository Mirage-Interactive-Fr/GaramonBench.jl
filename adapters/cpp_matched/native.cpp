#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <sstream>
#include <vector>

// Native decomposition of the exact packed workload exported by the Julia
// oracle. This is not a measurement of independent C++ plan construction.
struct NativePath { std::int64_t left, right, output; double factor; };
static_assert(sizeof(NativePath)==32, "unexpected path ABI");
extern "C" void garamon_packed_product(const void*,std::int64_t,const double*,
    const double*,double*,std::int64_t,std::int64_t,std::int64_t,std::int64_t) noexcept;
using Clock = std::chrono::steady_clock;
template<class T> void read_values(std::ifstream& input, std::vector<T>& values) {
    input.read(reinterpret_cast<char*>(values.data()), values.size()*sizeof(T));
    if (!input) throw std::runtime_error("truncated native input");
}
int main(int argc,char** argv) {
    try {
        if (argc!=2 && argc!=3) throw std::runtime_error("usage: garamon_native CASE.bin [SAMPLES.csv]");
        std::ofstream raw;
        if (argc==3) {
            raw.open(argv[2]);
            if (!raw) throw std::runtime_error("cannot write native samples");
            raw<<std::setprecision(17)<<"stage,sample,time_ms\n";
        }
        const auto load_start=Clock::now();
        std::ifstream input(argv[1],std::ios::binary);
        std::vector<std::int64_t> sizes(5); read_values(input,sizes);
        const auto np=sizes[0],nl=sizes[1],nr=sizes[2],no=sizes[3],h=sizes[4];
        if (np<1 || np>256 || nl<1 || nl>128 || nr<1 || nr>128 || no<1 || no>128 || h<1 || h>10000)
            throw std::runtime_error("invalid bounded native corpus");
        std::vector<NativePath> paths(np); read_values(input,paths);
        std::vector<double> left(nl*h),right(nr*h),expected(no*h),output(no*h,0.0);
        read_values(input,left); read_values(input,right); read_values(input,expected);
        for (const auto& p:paths)
            if (p.left<1 || p.left>nl || p.right<1 || p.right>nr || p.output<1 || p.output>no)
                throw std::runtime_error("invalid native path index");
        const auto elapsed=[](Clock::time_point start) {
            return std::chrono::duration<double,std::milli>(Clock::now()-start).count();
        };
        const double loading=elapsed(load_start);
        const auto kernel=[&](double* out) {
            garamon_packed_product(paths.data(),np,left.data(),right.data(),out,nl,nr,no,h);
        };
        const auto check=[&](const std::vector<double>& out) {
            if (out!=expected) throw std::runtime_error("native result differs from exact oracle");
        };
        const auto first_start=Clock::now(); kernel(output.data());
        const double first_ms=elapsed(first_start); check(output);
        std::cout<<std::setprecision(17)<<"stage,median_ms,p95_ms,samples,peak_rss_bytes,exact\n";
        const auto emit=[&](const char* stage,std::vector<double> times) {
            if (raw) for (std::size_t i=0;i<times.size();++i)
                raw<<stage<<','<<i+1<<','<<times[i]<<'\n';
            std::sort(times.begin(),times.end());
            // getrusage.ru_maxrss can retain the Julia parent's pre-exec peak.
            // VmHWM belongs to this executable's current address space.
            std::ifstream status("/proc/self/status"); std::string line;
            std::int64_t peak_rss=-1;
            while (std::getline(status,line)) if (line.compare(0,6,"VmHWM:")==0) {
                std::istringstream fields(line.substr(6)); fields>>peak_rss; peak_rss*=1024;
            }
            std::cout<<stage<<','<<times[times.size()/2]<<','
                <<times[static_cast<std::size_t>(.95*(times.size()-1))]<<','<<times.size()<<','
                <<peak_rss<<",true\n";
        };
        emit("load_exported_plan_and_data",{loading}); emit("first_kernel",{first_ms});
        // Timer overhead remains included. Small horizons are descriptive only.
        for (int mode=0;mode<3;++mode) {
            std::vector<double> times;
            for (int repeat=0;repeat<101;++repeat) {
                if (mode==0) std::fill(output.begin(),output.end(),0.0);
                const auto start=Clock::now();
                if (mode==2) {
                    std::vector<double> allocated(no*h,0.0); kernel(allocated.data());
                    times.push_back(elapsed(start)); check(allocated);
                } else {
                    if (mode==1) std::fill(output.begin(),output.end(),0.0);
                    kernel(output.data()); times.push_back(elapsed(start)); check(output);
                }
            }
            emit(mode==0 ? "kernel_preallocated_zeroed" : mode==1 ? "zero_and_kernel" : "allocate_zero_and_kernel",times);
        }
        return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
