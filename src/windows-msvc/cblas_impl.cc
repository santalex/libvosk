#ifdef __cplusplus
extern "C" {
#endif

#include "cblas.h"
#include "f2c.h"

static char get_trans(enum CBLAS_TRANSPOSE trans) {
    if (trans == CblasNoTrans) return 'N';
    if (trans == CblasTrans) return 'T';
    if (trans == CblasConjTrans) return 'C';
    return 'N';
}

static char get_uplo(enum CBLAS_UPLO uplo) {
    return (uplo == CblasUpper) ? 'U' : 'L';
}

static char get_diag(enum CBLAS_DIAG diag) {
    return (diag == CblasUnit) ? 'U' : 'N';
}

static char get_side(enum CBLAS_SIDE side) {
    return (side == CblasLeft) ? 'L' : 'R';
}

// ---------------------------------------------------------------------------
// Level 1 BLAS
// ---------------------------------------------------------------------------
float cblas_sdot(const int N, const float *X, const int incX, const float *Y, const int incY) {
    integer n = N, incx = incX, incy = incY;
    extern real sdot_(integer *, real *, integer *, real *, integer *);
    return (float)sdot_(&n, (real*)X, &incx, (real*)Y, &incy);
}

double cblas_ddot(const int N, const double *X, const int incX, const double *Y, const int incY) {
    integer n = N, incx = incX, incy = incY;
    extern doublereal ddot_(integer *, doublereal *, integer *, doublereal *, integer *);
    return (double)ddot_(&n, (doublereal*)X, &incx, (doublereal*)Y, &incy);
}

void cblas_scopy(const int N, const float *X, const int incX, float *Y, const int incY) {
    integer n = N, incx = incX, incy = incY;
    extern int scopy_(integer *, real *, integer *, real *, integer *);
    scopy_(&n, (real*)X, &incx, (real*)Y, &incy);
}

void cblas_dcopy(const int N, const double *X, const int incX, double *Y, const int incY) {
    integer n = N, incx = incX, incy = incY;
    extern int dcopy_(integer *, doublereal *, integer *, doublereal *, integer *);
    dcopy_(&n, (doublereal*)X, &incx, (doublereal*)Y, &incy);
}

void cblas_saxpy(const int N, const float alpha, const float *X, const int incX, float *Y, const int incY) {
    integer n = N, incx = incX, incy = incY;
    real a = alpha;
    extern int saxpy_(integer *, real *, real *, integer *, real *, integer *);
    saxpy_(&n, &a, (real*)X, &incx, (real*)Y, &incy);
}

void cblas_daxpy(const int N, const double alpha, const double *X, const int incX, double *Y, const int incY) {
    integer n = N, incx = incX, incy = incY;
    doublereal a = alpha;
    extern int daxpy_(integer *, doublereal *, doublereal *, integer *, doublereal *, integer *);
    daxpy_(&n, &a, (doublereal*)X, &incx, (doublereal*)Y, &incy);
}

void cblas_sscal(const int N, const float alpha, float *X, const int incX) {
    integer n = N, incx = incX;
    real a = alpha;
    extern int sscal_(integer *, real *, real *, integer *);
    sscal_(&n, &a, (real*)X, &incx);
}

void cblas_dscal(const int N, const double alpha, double *X, const int incX) {
    integer n = N, incx = incX;
    doublereal a = alpha;
    extern int dscal_(integer *, doublereal *, doublereal *, integer *);
    dscal_(&n, &a, (doublereal*)X, &incx);
}

float cblas_sasum(const int N, const float *X, const int incX) {
    integer n = N, incx = incX;
    extern real sasum_(integer *, real *, integer *);
    return (float)sasum_(&n, (real*)X, &incx);
}

double cblas_dasum(const int N, const double *X, const int incX) {
    integer n = N, incx = incX;
    extern doublereal dasum_(integer *, doublereal *, integer *);
    return (double)dasum_(&n, (doublereal*)X, &incx);
}

void cblas_srot(const int N, float *X, const int incX, float *Y, const int incY, const float c, const float s) {
    integer n = N, incx = incX, incy = incY;
    real c_ = c, s_ = s;
    extern int srot_(integer *, real *, integer *, real *, integer *, real *, real *);
    srot_(&n, (real*)X, &incx, (real*)Y, &incy, &c_, &s_);
}

void cblas_drot(const int N, double *X, const int incX, double *Y, const int incY, const double c, const double s) {
    integer n = N, incx = incX, incy = incY;
    doublereal c_ = c, s_ = s;
    extern int drot_(integer *, doublereal *, integer *, doublereal *, integer *, doublereal *, doublereal *);
    drot_(&n, (doublereal*)X, &incx, (doublereal*)Y, &incy, &c_, &s_);
}

// ---------------------------------------------------------------------------
// Level 2 BLAS
// ---------------------------------------------------------------------------
void cblas_sgemv(enum CBLAS_ORDER order, enum CBLAS_TRANSPOSE TransA, const int M, const int N,
                 const float alpha, const float *A, const int lda, const float *X, const int incX,
                 const float beta, float *Y, const int incY) {
    char trans = get_trans(TransA);
    integer m = M, n = N, lda_ = lda, incx = incX, incy = incY;
    real a = alpha, b = beta;
    extern int sgemv_(char *, integer *, integer *, real *, real *, integer *, real *, integer *, real *, real *, integer *);
    if (order == CblasColMajor) {
        sgemv_(&trans, &m, &n, &a, (real*)A, &lda_, (real*)X, &incx, &b, (real*)Y, &incy);
    } else {
        char trans_r = (trans == 'N') ? 'T' : 'N';
        sgemv_(&trans_r, &n, &m, &a, (real*)A, &lda_, (real*)X, &incx, &b, (real*)Y, &incy);
    }
}

void cblas_dgemv(enum CBLAS_ORDER order, enum CBLAS_TRANSPOSE TransA, const int M, const int N,
                 const double alpha, const double *A, const int lda, const double *X, const int incX,
                 const double beta, double *Y, const int incY) {
    char trans = get_trans(TransA);
    integer m = M, n = N, lda_ = lda, incx = incX, incy = incY;
    doublereal a = alpha, b = beta;
    extern int dgemv_(char *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dgemv_(&trans, &m, &n, &a, (doublereal*)A, &lda_, (doublereal*)X, &incx, &b, (doublereal*)Y, &incy);
    } else {
        char trans_r = (trans == 'N') ? 'T' : 'N';
        dgemv_(&trans_r, &n, &m, &a, (doublereal*)A, &lda_, (doublereal*)X, &incx, &b, (doublereal*)Y, &incy);
    }
}

void cblas_sgbmv(enum CBLAS_ORDER order, enum CBLAS_TRANSPOSE TransA, const int M, const int N,
                 const int KL, const int KU, const float alpha, const float *A, const int lda,
                 const float *X, const int incX, const float beta, float *Y, const int incY) {
    char trans = get_trans(TransA);
    integer m = M, n = N, kl = KL, ku = KU, lda_ = lda, incx = incX, incy = incY;
    real a = alpha, b = beta;
    extern int sgbmv_(char *, integer *, integer *, integer *, integer *, real *, real *, integer *, real *, integer *, real *, real *, integer *);
    sgbmv_(&trans, &m, &n, &kl, &ku, &a, (real*)A, &lda_, (real*)X, &incx, &b, (real*)Y, &incy);
}

void cblas_dgbmv(enum CBLAS_ORDER order, enum CBLAS_TRANSPOSE TransA, const int M, const int N,
                 const int KL, const int KU, const double alpha, const double *A, const int lda,
                 const double *X, const int incX, const double beta, double *Y, const int incY) {
    char trans = get_trans(TransA);
    integer m = M, n = N, kl = KL, ku = KU, lda_ = lda, incx = incX, incy = incY;
    doublereal a = alpha, b = beta;
    extern int dgbmv_(char *, integer *, integer *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    dgbmv_(&trans, &m, &n, &kl, &ku, &a, (doublereal*)A, &lda_, (doublereal*)X, &incx, &b, (doublereal*)Y, &incy);
}

void cblas_sger(enum CBLAS_ORDER order, const int M, const int N, const float alpha,
                const float *X, const int incX, const float *Y, const int incY, float *A, const int lda) {
    integer m = M, n = N, lda_ = lda, incx = incX, incy = incY;
    real a = alpha;
    extern int sger_(integer *, integer *, real *, real *, integer *, real *, integer *, real *, integer *);
    if (order == CblasColMajor) {
        sger_(&m, &n, &a, (real*)X, &incx, (real*)Y, &incy, (real*)A, &lda_);
    } else {
        sger_(&n, &m, &a, (real*)Y, &incy, (real*)X, &incx, (real*)A, &lda_);
    }
}

void cblas_dger(enum CBLAS_ORDER order, const int M, const int N, const double alpha,
                const double *X, const int incX, const double *Y, const int incY, double *A, const int lda) {
    integer m = M, n = N, lda_ = lda, incx = incX, incy = incY;
    doublereal a = alpha;
    extern int dger_(integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dger_(&m, &n, &a, (doublereal*)X, &incx, (doublereal*)Y, &incy, (doublereal*)A, &lda_);
    } else {
        dger_(&n, &m, &a, (doublereal*)Y, &incy, (doublereal*)X, &incx, (doublereal*)A, &lda_);
    }
}

void cblas_ssymv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const float alpha,
                 const float *A, const int lda, const float *X, const int incX, const float beta, float *Y, const int incY) {
    char uplo = get_uplo(Uplo);
    integer n = N, lda_ = lda, incx = incX, incy = incY;
    real a = alpha, b = beta;
    extern int ssymv_(char *, integer *, real *, real *, integer *, real *, integer *, real *, real *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    ssymv_(&uplo, &n, &a, (real*)A, &lda_, (real*)X, &incx, &b, (real*)Y, &incy);
}

void cblas_dsymv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const double alpha,
                 const double *A, const int lda, const double *X, const int incX, const double beta, double *Y, const int incY) {
    char uplo = get_uplo(Uplo);
    integer n = N, lda_ = lda, incx = incX, incy = incY;
    doublereal a = alpha, b = beta;
    extern int dsymv_(char *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    dsymv_(&uplo, &n, &a, (doublereal*)A, &lda_, (doublereal*)X, &incx, &b, (doublereal*)Y, &incy);
}

void cblas_sspmv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const float alpha,
                 const float *Ap, const float *X, const int incX, const float beta, float *Y, const int incY) {
    char uplo = get_uplo(Uplo);
    integer n = N, incx = incX, incy = incY;
    real a = alpha, b = beta;
    extern int sspmv_(char *, integer *, real *, real *, real *, integer *, real *, real *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    sspmv_(&uplo, &n, &a, (real*)Ap, (real*)X, &incx, &b, (real*)Y, &incy);
}

void cblas_dspmv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const double alpha,
                 const double *Ap, const double *X, const int incX, const double beta, double *Y, const int incY) {
    char uplo = get_uplo(Uplo);
    integer n = N, incx = incX, incy = incY;
    doublereal a = alpha, b = beta;
    extern int dspmv_(char *, integer *, doublereal *, doublereal *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    dspmv_(&uplo, &n, &a, (doublereal*)Ap, (doublereal*)X, &incx, &b, (doublereal*)Y, &incy);
}

void cblas_sspr(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const float alpha,
                const float *X, const int incX, float *Ap) {
    char uplo = get_uplo(Uplo);
    integer n = N, incx = incX;
    real a = alpha;
    extern int sspr_(char *, integer *, real *, real *, integer *, real *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    sspr_(&uplo, &n, &a, (real*)X, &incx, (real*)Ap);
}

void cblas_dspr(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const double alpha,
                const double *X, const int incX, double *Ap) {
    char uplo = get_uplo(Uplo);
    integer n = N, incx = incX;
    doublereal a = alpha;
    extern int dspr_(char *, integer *, doublereal *, doublereal *, integer *, doublereal *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    dspr_(&uplo, &n, &a, (doublereal*)X, &incx, (doublereal*)Ap);
}

void cblas_sspr2(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const float alpha,
                 const float *X, const int incX, const float *Y, const int incY, float *A) {
    char uplo = get_uplo(Uplo);
    integer n = N, incx = incX, incy = incY;
    real a = alpha;
    extern int sspr2_(char *, integer *, real *, real *, integer *, real *, integer *, real *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    sspr2_(&uplo, &n, &a, (real*)X, &incx, (real*)Y, &incy, (real*)A);
}

void cblas_dspr2(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, const int N, const double alpha,
                 const double *X, const int incX, const double *Y, const int incY, double *A) {
    char uplo = get_uplo(Uplo);
    integer n = N, incx = incX, incy = incY;
    doublereal a = alpha;
    extern int dspr2_(char *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
    }
    dspr2_(&uplo, &n, &a, (doublereal*)X, &incx, (doublereal*)Y, &incy, (doublereal*)A);
}

void cblas_stpmv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, enum CBLAS_TRANSPOSE TransA,
                 enum CBLAS_DIAG Diag, const int N, const float *Ap, float *X, const int incX) {
    char uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer n = N, incx = incX;
    extern int stpmv_(char *, char *, char *, integer *, real *, real *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
        trans = (trans == 'N') ? 'T' : 'N';
    }
    stpmv_(&uplo, &trans, &diag, &n, (real*)Ap, (real*)X, &incx);
}

void cblas_dtpmv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, enum CBLAS_TRANSPOSE TransA,
                 enum CBLAS_DIAG Diag, const int N, const double *Ap, double *X, const int incX) {
    char uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer n = N, incx = incX;
    extern int dtpmv_(char *, char *, char *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
        trans = (trans == 'N') ? 'T' : 'N';
    }
    dtpmv_(&uplo, &trans, &diag, &n, (doublereal*)Ap, (doublereal*)X, &incx);
}

void cblas_stpsv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, enum CBLAS_TRANSPOSE TransA,
                 enum CBLAS_DIAG Diag, const int N, const float *Ap, float *X, const int incX) {
    char uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer n = N, incx = incX;
    extern int stpsv_(char *, char *, char *, integer *, real *, real *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
        trans = (trans == 'N') ? 'T' : 'N';
    }
    stpsv_(&uplo, &trans, &diag, &n, (real*)Ap, (real*)X, &incx);
}

void cblas_dtpsv(enum CBLAS_ORDER order, enum CBLAS_UPLO Uplo, enum CBLAS_TRANSPOSE TransA,
                 enum CBLAS_DIAG Diag, const int N, const double *Ap, double *X, const int incX) {
    char uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer n = N, incx = incX;
    extern int dtpsv_(char *, char *, char *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasRowMajor) {
        uplo = (uplo == 'U') ? 'L' : 'U';
        trans = (trans == 'N') ? 'T' : 'N';
    }
    dtpsv_(&uplo, &trans, &diag, &n, (doublereal*)Ap, (doublereal*)X, &incx);
}

// ---------------------------------------------------------------------------
// Level 3 BLAS
// ---------------------------------------------------------------------------
void cblas_sgemm(enum CBLAS_ORDER order, enum CBLAS_TRANSPOSE TransA, enum CBLAS_TRANSPOSE TransB,
                 const int M, const int N, const int K, const float alpha, const float *A, const int lda,
                 const float *B, const int ldb, const float beta, float *C, const int ldc) {
    char ta = get_trans(TransA), tb = get_trans(TransB);
    integer m = M, n = N, k = K, lda_ = lda, ldb_ = ldb, ldc_ = ldc;
    real a = alpha, b = beta;
    extern int sgemm_(char *, char *, integer *, integer *, integer *, real *, real *, integer *, real *, integer *, real *, real *, integer *);
    if (order == CblasColMajor) {
        sgemm_(&ta, &tb, &m, &n, &k, &a, (real*)A, &lda_, (real*)B, &ldb_, &b, (real*)C, &ldc_);
    } else {
        sgemm_(&tb, &ta, &n, &m, &k, &a, (real*)B, &ldb_, (real*)A, &lda_, &b, (real*)C, &ldc_);
    }
}

void cblas_dgemm(enum CBLAS_ORDER order, enum CBLAS_TRANSPOSE TransA, enum CBLAS_TRANSPOSE TransB,
                 const int M, const int N, const int K, const double alpha, const double *A, const int lda,
                 const double *B, const int ldb, const double beta, double *C, const int ldc) {
    char ta = get_trans(TransA), tb = get_trans(TransB);
    integer m = M, n = N, k = K, lda_ = lda, ldb_ = ldb, ldc_ = ldc;
    doublereal a = alpha, b = beta;
    extern int dgemm_(char *, char *, integer *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dgemm_(&ta, &tb, &m, &n, &k, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_, &b, (doublereal*)C, &ldc_);
    } else {
        dgemm_(&tb, &ta, &n, &m, &k, &a, (doublereal*)B, &ldb_, (doublereal*)A, &lda_, &b, (doublereal*)C, &ldc_);
    }
}

void cblas_strmm(enum CBLAS_ORDER order, enum CBLAS_SIDE Side, enum CBLAS_UPLO Uplo,
                 enum CBLAS_TRANSPOSE TransA, enum CBLAS_DIAG Diag, const int M, const int N,
                 const float alpha, const float *A, const int lda, float *B, const int ldb) {
    char side = get_side(Side), uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer m = M, n = N, lda_ = lda, ldb_ = ldb;
    real a = alpha;
    extern int strmm_(char *, char *, char *, char *, integer *, integer *, real *, real *, integer *, real *, integer *);
    if (order == CblasColMajor) {
        strmm_(&side, &uplo, &trans, &diag, &m, &n, &a, (real*)A, &lda_, (real*)B, &ldb_);
    } else {
        char side_r = (side == 'L') ? 'R' : 'L';
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        strmm_(&side_r, &uplo_r, &trans, &diag, &n, &m, &a, (real*)A, &lda_, (real*)B, &ldb_);
    }
}

void cblas_dtrmm(enum CBLAS_ORDER order, enum CBLAS_SIDE Side, enum CBLAS_UPLO Uplo,
                 enum CBLAS_TRANSPOSE TransA, enum CBLAS_DIAG Diag, const int M, const int N,
                 const double alpha, const double *A, const int lda, double *B, const int ldb) {
    char side = get_side(Side), uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer m = M, n = N, lda_ = lda, ldb_ = ldb;
    doublereal a = alpha;
    extern int dtrmm_(char *, char *, char *, char *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dtrmm_(&side, &uplo, &trans, &diag, &m, &n, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_);
    } else {
        char side_r = (side == 'L') ? 'R' : 'L';
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        dtrmm_(&side_r, &uplo_r, &trans, &diag, &n, &m, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_);
    }
}

void cblas_strsm(enum CBLAS_ORDER order, enum CBLAS_SIDE Side, enum CBLAS_UPLO Uplo,
                 enum CBLAS_TRANSPOSE TransA, enum CBLAS_DIAG Diag, const int M, const int N,
                 const float alpha, const float *A, const int lda, float *B, const int ldb) {
    char side = get_side(Side), uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer m = M, n = N, lda_ = lda, ldb_ = ldb;
    real a = alpha;
    extern int strsm_(char *, char *, char *, char *, integer *, integer *, real *, real *, integer *, real *, integer *);
    if (order == CblasColMajor) {
        strsm_(&side, &uplo, &trans, &diag, &m, &n, &a, (real*)A, &lda_, (real*)B, &ldb_);
    } else {
        char side_r = (side == 'L') ? 'R' : 'L';
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        strsm_(&side_r, &uplo_r, &trans, &diag, &n, &m, &a, (real*)A, &lda_, (real*)B, &ldb_);
    }
}

void cblas_dtrsm(enum CBLAS_ORDER order, enum CBLAS_SIDE Side, enum CBLAS_UPLO Uplo,
                 enum CBLAS_TRANSPOSE TransA, enum CBLAS_DIAG Diag, const int M, const int N,
                 const double alpha, const double *A, const int lda, double *B, const int ldb) {
    char side = get_side(Side), uplo = get_uplo(Uplo), trans = get_trans(TransA), diag = get_diag(Diag);
    integer m = M, n = N, lda_ = lda, ldb_ = ldb;
    doublereal a = alpha;
    extern int dtrsm_(char *, char *, char *, char *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dtrsm_(&side, &uplo, &trans, &diag, &m, &n, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_);
    } else {
        char side_r = (side == 'L') ? 'R' : 'L';
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        dtrsm_(&side_r, &uplo_r, &trans, &diag, &n, &m, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_);
    }
}
void cblas_ssymm(const enum CBLAS_ORDER order, const enum CBLAS_SIDE Side,
                 const enum CBLAS_UPLO Uplo, const int M, const int N,
                 const float alpha, const float *A, const int lda,
                 const float *B, const int ldb, const float beta,
                 float *C, const int ldc) {
    char side = get_side(Side), uplo = get_uplo(Uplo);
    integer m = M, n = N, lda_ = lda, ldb_ = ldb, ldc_ = ldc;
    real a = alpha, b = beta;
    extern int ssymm_(char *, char *, integer *, integer *, real *, real *, integer *, real *, integer *, real *, real *, integer *);
    if (order == CblasColMajor) {
        ssymm_(&side, &uplo, &m, &n, &a, (real*)A, &lda_, (real*)B, &ldb_, &b, (real*)C, &ldc_);
    } else {
        char side_r = (side == 'L') ? 'R' : 'L';
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        ssymm_(&side_r, &uplo_r, &n, &m, &a, (real*)A, &lda_, (real*)B, &ldb_, &b, (real*)C, &ldc_);
    }
}

void cblas_dsymm(const enum CBLAS_ORDER order, const enum CBLAS_SIDE Side,
                 const enum CBLAS_UPLO Uplo, const int M, const int N,
                 const double alpha, const double *A, const int lda,
                 const double *B, const int ldb, const double beta,
                 double *C, const int ldc) {
    char side = get_side(Side), uplo = get_uplo(Uplo);
    integer m = M, n = N, lda_ = lda, ldb_ = ldb, ldc_ = ldc;
    doublereal a = alpha, b = beta;
    extern int dsymm_(char *, char *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dsymm_(&side, &uplo, &m, &n, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_, &b, (doublereal*)C, &ldc_);
    } else {
        char side_r = (side == 'L') ? 'R' : 'L';
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        dsymm_(&side_r, &uplo_r, &n, &m, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_, &b, (doublereal*)C, &ldc_);
    }
}

void cblas_ssyrk(const enum CBLAS_ORDER order, const enum CBLAS_UPLO Uplo,
                 const enum CBLAS_TRANSPOSE Trans, const int N, const int K,
                 const float alpha, const float *A, const int lda,
                 const float beta, float *C, const int ldc) {
    char uplo = get_uplo(Uplo), trans = get_trans(Trans);
    integer n = N, k = K, lda_ = lda, ldc_ = ldc;
    real a = alpha, b = beta;
    extern int ssyrk_(char *, char *, integer *, integer *, real *, real *, integer *, real *, real *, integer *);
    if (order == CblasColMajor) {
        ssyrk_(&uplo, &trans, &n, &k, &a, (real*)A, &lda_, &b, (real*)C, &ldc_);
    } else {
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        char trans_r = (trans == 'N') ? 'T' : 'N';
        ssyrk_(&uplo_r, &trans_r, &n, &k, &a, (real*)A, &lda_, &b, (real*)C, &ldc_);
    }
}

void cblas_dsyrk(const enum CBLAS_ORDER order, const enum CBLAS_UPLO Uplo,
                 const enum CBLAS_TRANSPOSE Trans, const int N, const int K,
                 const double alpha, const double *A, const int lda,
                 const double beta, double *C, const int ldc) {
    char uplo = get_uplo(Uplo), trans = get_trans(Trans);
    integer n = N, k = K, lda_ = lda, ldc_ = ldc;
    doublereal a = alpha, b = beta;
    extern int dsyrk_(char *, char *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dsyrk_(&uplo, &trans, &n, &k, &a, (doublereal*)A, &lda_, &b, (doublereal*)C, &ldc_);
    } else {
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        char trans_r = (trans == 'N') ? 'T' : 'N';
        dsyrk_(&uplo_r, &trans_r, &n, &k, &a, (doublereal*)A, &lda_, &b, (doublereal*)C, &ldc_);
    }
}

void cblas_ssyr2k(const enum CBLAS_ORDER order, const enum CBLAS_UPLO Uplo,
                  const enum CBLAS_TRANSPOSE Trans, const int N, const int K,
                  const float alpha, const float *A, const int lda,
                  const float *B, const int ldb, const float beta,
                  float *C, const int ldc) {
    char uplo = get_uplo(Uplo), trans = get_trans(Trans);
    integer n = N, k = K, lda_ = lda, ldb_ = ldb, ldc_ = ldc;
    real a = alpha, b = beta;
    extern int ssyr2k_(char *, char *, integer *, integer *, real *, real *, integer *, real *, integer *, real *, real *, integer *);
    if (order == CblasColMajor) {
        ssyr2k_(&uplo, &trans, &n, &k, &a, (real*)A, &lda_, (real*)B, &ldb_, &b, (real*)C, &ldc_);
    } else {
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        char trans_r = (trans == 'N') ? 'T' : 'N';
        ssyr2k_(&uplo_r, &trans_r, &n, &k, &a, (real*)A, &lda_, (real*)B, &ldb_, &b, (real*)C, &ldc_);
    }
}

void cblas_dsyr2k(const enum CBLAS_ORDER order, const enum CBLAS_UPLO Uplo,
                  const enum CBLAS_TRANSPOSE Trans, const int N, const int K,
                  const double alpha, const double *A, const int lda,
                  const double *B, const int ldb, const double beta,
                  double *C, const int ldc) {
    char uplo = get_uplo(Uplo), trans = get_trans(Trans);
    integer n = N, k = K, lda_ = lda, ldb_ = ldb, ldc_ = ldc;
    doublereal a = alpha, b = beta;
    extern int dsyr2k_(char *, char *, integer *, integer *, doublereal *, doublereal *, integer *, doublereal *, integer *, doublereal *, doublereal *, integer *);
    if (order == CblasColMajor) {
        dsyr2k_(&uplo, &trans, &n, &k, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_, &b, (doublereal*)C, &ldc_);
    } else {
        char uplo_r = (uplo == 'U') ? 'L' : 'U';
        char trans_r = (trans == 'N') ? 'T' : 'N';
        dsyr2k_(&uplo_r, &trans_r, &n, &k, &a, (doublereal*)A, &lda_, (doublereal*)B, &ldb_, &b, (doublereal*)C, &ldc_);
    }
}

#ifdef __cplusplus
}
#endif
