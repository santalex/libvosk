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

// Direct OpenBLAS LAPACK function bridges for Kaldi matrix cblas-wrappers
extern "C" {
    int LAPACK_ssptrf(char const* uplo, int const* n, float* ap, int* ipiv, int* info, size_t uplo_len);
    int LAPACK_dsptrf(char const* uplo, int const* n, double* ap, int* ipiv, int* info, size_t uplo_len);
    int LAPACK_ssptri(char const* uplo, int const* n, float* ap, int* ipiv, float* work, int* info, size_t uplo_len);
    int LAPACK_dsptri(char const* uplo, int const* n, double* ap, int* ipiv, double* work, int* info, size_t uplo_len);
    int LAPACK_stptri(char const* uplo, char const* diag, int const* n, float* ap, int* info, size_t uplo_len, size_t diag_len);
    int LAPACK_dtptri(char const* uplo, char const* diag, int const* n, double* ap, int* info, size_t uplo_len, size_t diag_len);
    int LAPACK_sgesvd(char const* jobu, char const* jobvt, int const* m, int const* n, float* a, int const* lda, float* s, float* u, int const* ldu, float* vt, int const* ldvt, float* work, int const* lwork, int* info, size_t jobu_len, size_t jobvt_len);
    int LAPACK_dgesvd(char const* jobu, char const* jobvt, int const* m, int const* n, double* a, int const* lda, double* s, double* u, int const* ldu, double* vt, int const* ldvt, double* work, int const* lwork, int* info, size_t jobu_len, size_t jobvt_len);

    inline void ssptrf_(char *uplo, int *n, float *ap, int *ipiv, int *info) {
        LAPACK_ssptrf(uplo, n, ap, ipiv, info, 1);
    }
    inline void dsptrf_(char *uplo, int *n, double *ap, int *ipiv, int *info) {
        LAPACK_dsptrf(uplo, n, ap, ipiv, info, 1);
    }
    inline void ssptri_(char *uplo, int *n, float *ap, int *ipiv, float *work, int *info) {
        LAPACK_ssptri(uplo, n, ap, ipiv, work, info, 1);
    }
    inline void dsptri_(char *uplo, int *n, double *ap, int *ipiv, double *work, int *info) {
        LAPACK_dsptri(uplo, n, ap, ipiv, work, info, 1);
    }
    inline void stptri_(char *uplo, char *diag, int *n, float *ap, int *info) {
        LAPACK_stptri(uplo, diag, n, ap, info, 1, 1);
    }
    inline void dtptri_(char *uplo, char *diag, int *n, double *ap, int *info) {
        LAPACK_dtptri(uplo, diag, n, ap, info, 1, 1);
    }
    inline void sgesvd_(char *jobu, char *jobvt, int *m, int *n, float *a, int *lda, float *s, float *u, int *ldu, float *vt, int *ldvt, float *work, int *lwork, int *info) {
        LAPACK_sgesvd(jobu, jobvt, m, n, a, lda, s, u, ldu, vt, ldvt, work, lwork, info, 1, 1);
    }
    inline void dgesvd_(char *jobu, char *jobvt, int *m, int *n, double *a, int *lda, double *s, double *u, int *ldu, double *vt, int *ldvt, double *work, int *lwork, int *info) {
        LAPACK_dgesvd(jobu, jobvt, m, n, a, lda, s, u, ldu, vt, ldvt, work, lwork, info, 1, 1);
    }
}

#endif
