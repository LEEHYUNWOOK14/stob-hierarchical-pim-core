#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>

#include "half.h"

static half_float::half fromBits(uint16_t bits)
{
    half_float::half value;
    static_assert(sizeof(value) == sizeof(bits), "unexpected half storage size");
    std::memcpy(&value, &bits, sizeof(bits));
    return value;
}

static uint16_t toBits(half_float::half value)
{
    uint16_t bits;
    std::memcpy(&bits, &value, sizeof(bits));
    return bits;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        std::cerr << "usage: generate_fp16_add_vectors OUTPUT\n";
        return 2;
    }
    std::ofstream output(argv[1]);
    if (!output) return 3;
    std::mt19937 generator(0x48424d32u);
    std::uniform_int_distribution<uint32_t> bits(0, 0xffff);
    output << std::hex << std::setfill('0');
    for (unsigned index = 0; index < 4096; ++index) {
        uint16_t lhs = static_cast<uint16_t>(bits(generator));
        uint16_t rhs = static_cast<uint16_t>(bits(generator));
        if ((lhs & 0x7c00) == 0x7c00) lhs ^= 0x0400;
        if ((rhs & 0x7c00) == 0x7c00) rhs ^= 0x0400;
        uint16_t result = toBits(fromBits(lhs) + fromBits(rhs));
        output << std::setw(4) << lhs << ' ' << std::setw(4) << rhs << ' '
               << std::setw(4) << result << '\n';
    }
}
