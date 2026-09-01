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
#include <string_view>

#ifndef ssize_t
typedef intptr_t ssize_t;
#endif

// GCC/Clang built-ins fallback for MSVC
inline int __builtin_popcountll(unsigned long long x) {
    return (int)__popcnt64(x);
}

inline int __builtin_ctzll(unsigned long long x) {
    unsigned long idx = 0;
    if (_BitScanForward64(&idx, x)) return (int)idx;
    return 64;
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

// Direct OpenBLAS LAPACK function mappings for Kaldi matrix cblas-wrappers (with Fortran string lengths)
#define stptri_(uplo, diag, n, ap, info) LAPACK_stptri(uplo, diag, n, ap, info, 1, 1)
#define dtptri_(uplo, diag, n, ap, info) LAPACK_dtptri(uplo, diag, n, ap, info, 1, 1)
#define ssptrf_(uplo, n, ap, ipiv, info) LAPACK_ssptrf(uplo, n, ap, ipiv, info, 1)
#define dsptrf_(uplo, n, ap, ipiv, info) LAPACK_dsptrf(uplo, n, ap, ipiv, info, 1)
#define ssptri_(uplo, n, ap, ipiv, work, info) LAPACK_ssptri(uplo, n, ap, ipiv, work, info, 1)
#define dsptri_(uplo, n, ap, ipiv, work, info) LAPACK_dsptri(uplo, n, ap, ipiv, work, info, 1)
#define sgesvd_(jobu, jobvt, m, n, a, lda, s, u, ldu, vt, ldvt, work, lwork, info) LAPACK_sgesvd(jobu, jobvt, m, n, a, lda, s, u, ldu, vt, ldvt, work, lwork, info, 1, 1)
#define dgesvd_(jobu, jobvt, m, n, a, lda, s, u, ldu, vt, ldvt, work, lwork, info) LAPACK_dgesvd(jobu, jobvt, m, n, a, lda, s, u, ldu, vt, ldvt, work, lwork, info, 1, 1)

#endif
