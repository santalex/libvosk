#pragma once
#ifdef _MSC_VER

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <intrin.h>
#include <cstdint>
#include <cstddef>
#include <cctype>
#include <cwctype>
#include <algorithm>
#include <cmath>
#include <string_view>

#ifndef ssize_t
typedef intptr_t ssize_t;
#endif

// Undefine any macro pollution that could break C++ standard library
#ifdef isalnum
#undef isalnum
#endif
#ifdef isalpha
#undef isalpha
#endif
#ifdef iscntrl
#undef iscntrl
#endif
#ifdef isdigit
#undef isdigit
#endif
#ifdef isgraph
#undef isgraph
#endif
#ifdef islower
#undef islower
#endif
#ifdef isprint
#undef isprint
#endif
#ifdef ispunct
#undef ispunct
#endif
#ifdef isspace
#undef isspace
#endif
#ifdef isupper
#undef isupper
#endif
#ifdef isxdigit
#undef isxdigit
#endif
#ifdef tolower
#undef tolower
#endif
#ifdef toupper
#undef toupper
#endif
#ifdef isblank
#undef isblank
#endif

// GCC/Clang built-ins fallback for MSVC
inline int __builtin_popcountll(unsigned long long x) {
#if defined(_M_X64) || defined(_M_ARM64)
    return (int)__popcnt64(x);
#else
    return (int)(__popcnt((unsigned int)x) + __popcnt((unsigned int)(x >> 32)));
#endif
}

inline int __builtin_ctzll(unsigned long long x) {
#if defined(_M_X64) || defined(_M_ARM64)
    unsigned long idx = 0;
    if (_BitScanForward64(&idx, x)) return (int)idx;
    return 64;
#else
    unsigned long idx = 0;
    if (_BitScanForward(&idx, (unsigned long)x)) return (int)idx;
    if (_BitScanForward(&idx, (unsigned long)(x >> 32))) return (int)(idx + 32);
    return 64;
#endif
}

inline int __builtin_popcount(unsigned int x) {
    return (int)__popcnt(x);
}

inline int __builtin_ctz(unsigned int x) {
    unsigned long idx = 0;
    if (_BitScanForward(&idx, x)) return (int)idx;
    return 32;
}

// Undefine conflicting Windows SDK macros
#ifdef PASSTHROUGH
#undef PASSTHROUGH
#endif

#ifdef ERROR
#undef ERROR
#endif

#ifdef IGNORE
#undef IGNORE
#endif

#ifdef DELETE
#undef DELETE
#endif

#ifdef CONST
#undef CONST
#endif

#endif

