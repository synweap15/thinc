from libc.stdint cimport int32_t
from libc.string cimport memcpy
from libc.math cimport exp as c_exp
from cymem.cymem cimport Pool

from .typedefs cimport weight_t


cdef class Matrix:
    cdef Pool mem
    cdef weight_t* data
    cdef int32_t nr_row
    cdef int32_t nr_col


cdef class Vec:
    @staticmethod
    cdef inline weight_t max(const weight_t* x, int32_t nr) nogil:
        if nr == 0:
            return 0
        cdef int i
        cdef weight_t mode = x[0]
        for i in range(1, nr):
            if x[i] > mode:
                mode = x[i]
        return mode

    @staticmethod
    cdef inline weight_t sum(const weight_t* vec, int32_t nr) nogil:
        cdef int i
        cdef weight_t total = 0
        for i in range(nr):
            total += vec[i]
        return total

    @staticmethod
    cdef inline void add(weight_t* output, const weight_t* x,
                           weight_t inc, int32_t nr) nogil:
        memcpy(output, x, sizeof(output[0]) * nr)
        Vec.add_i(output, inc, nr)

    @staticmethod
    cdef inline void add_i(weight_t* vec, weight_t inc, int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            vec[i] += inc

    @staticmethod
    cdef inline void mul(weight_t* output, const weight_t* vec, weight_t scal,
                         int32_t nr) nogil:
        memcpy(output, vec, sizeof(output[0]) * nr)
        Vec.mul_i(output, scal, nr)

    @staticmethod
    cdef inline void mul_i(weight_t* vec, const weight_t scal, int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            vec[i] *= scal

    @staticmethod
    cdef inline void div(weight_t* output, const weight_t* vec, weight_t scal,
                         int32_t nr) nogil:
        memcpy(output, vec, sizeof(output[0]) * nr)
        Vec.div_i(output, scal, nr)

    @staticmethod
    cdef inline void div_i(weight_t* vec, const weight_t scal, int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            vec[i] /= scal

    @staticmethod
    cdef inline void exp(weight_t* output, const weight_t* vec, int32_t nr) nogil:
        memcpy(output, vec, sizeof(output[0]) * nr)
        Vec.exp_i(output, nr)

    @staticmethod
    cdef inline void exp_i(weight_t* vec, int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            vec[i] = c_exp(vec[i])

    @staticmethod
    cdef inline void reciprocal_i(weight_t* vec, int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            vec[i] = 1.0 / vec[i]


cdef class VecVec:
    @staticmethod
    cdef inline void add(weight_t* output,
                         const weight_t* x, 
                         const weight_t* y,
                         weight_t scale,
                         int32_t nr) nogil:
        memcpy(output, x, sizeof(output[0]) * nr)
        VecVec.add_i(output, y, scale, nr)
   
    @staticmethod
    cdef inline void add_i(weight_t* x, 
                           const weight_t* y,
                           weight_t scale,
                           int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            x[i] += y[i] * scale
 
    @staticmethod
    cdef inline void add_pow(weight_t* output,
                         const weight_t* x, 
                         const weight_t* y,
                         weight_t power,
                         int32_t nr) nogil:
        memcpy(output, x, sizeof(output[0]) * nr)
        VecVec.add_pow_i(output, y, power, nr)

   
    @staticmethod
    cdef inline void add_pow_i(weight_t* x, 
                               const weight_t* y,
                               weight_t power,
                               int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            x[i] += y[i] ** power
 
    @staticmethod
    cdef inline void mul(weight_t* output,
                         const weight_t* x, 
                         const weight_t* y,
                         int32_t nr) nogil:
        memcpy(output, x, sizeof(output[0]) * nr)
        VecVec.mul_i(output, y, nr)
   
    @staticmethod
    cdef inline void mul_i(weight_t* x, 
                           const weight_t* y,
                           int32_t nr) nogil:
        cdef int i
        for i in range(nr):
            x[i] *= y[i]

 
    @staticmethod
    cdef inline weight_t dot(const weight_t* x, 
                             const weight_t* y,
                             int32_t nr) nogil:
        cdef int i
        cdef weight_t total = 0
        for i in range(nr):
            total += x[i] * y[i]
        return total
 

cdef class MatVec:
    @staticmethod
    cdef inline void mul(weight_t* output,
                         const weight_t* mat,
                         const weight_t* vec,
                         int32_t nr_row, int32_t nr_col) nogil:
        memcpy(output, mat, sizeof(output[0]) * nr_row * nr_col)
        MatVec.mul_i(output, vec, nr_row, nr_col)

    @staticmethod
    cdef inline void mul_i(weight_t* mat,
                           const weight_t* vec,
                           int32_t nr_row, int32_t nr_col) nogil:
        cdef int i, row, col
        for i in range(nr_row):
            row = i * nr_col
            for col in range(nr_col):
                mat[row + col] *= vec[col]

    @staticmethod
    cdef inline void dot(weight_t* output,
                         const weight_t* mat,
                         const weight_t* vec,
                         int32_t nr_row, int32_t nr_col) nogil:
        cdef int i, row, col
        for i in range(nr_row):
            output[i] = 0
            row = i * nr_col
            for col in range(nr_col):
                output[i] += mat[row + col] * vec[col]

    @staticmethod
    cdef inline void T_dot_i(weight_t* vec,
                             const weight_t* mat,
                             int32_t nr_row,
                             int32_t nr_col) nogil:
        cdef int i, row, col
        cdef weight_t total = 0.0
        cdef weight_t value
        for col in range(nr_col):
            value = vec[col]
            total = 0
            for row in range(nr_row):
                total += value * mat[(row * nr_col) + col]
            vec[col] = total


cdef class MatMat:
    @staticmethod
    cdef inline void add(weight_t* output,
                         const weight_t* x,
                         const weight_t* y,
                         int32_t nr_row, int32_t nr_col) nogil:
        memcpy(output, x, sizeof(output[0]) * nr_row * nr_col)
        MatMat.add_i(output, y, nr_row, nr_col)

    @staticmethod
    cdef inline void add_i(weight_t* x,
                           const weight_t* y,
                           int32_t nr_row, int32_t nr_col) nogil:
        cdef int i, row, col
        for i in range(nr_row):
            row = i * nr_col
            for col in range(nr_col):
                x[row + col] += y[row + col]

    @staticmethod
    cdef inline void mul(weight_t* output,
                         const weight_t* x,
                         const weight_t* y,
                         int32_t nr_row, int32_t nr_col) nogil:
        memcpy(output, x, sizeof(output[0]) * nr_row * nr_col)
        MatMat.mul_i(output, y, nr_row, nr_col)

    @staticmethod
    cdef inline void mul_i(weight_t* x,
                           const weight_t* y,
                           int32_t nr_row, int32_t nr_col) nogil:
        cdef int i, row, col
        for i in range(nr_row):
            row = i * nr_col
            for col in range(nr_col):
                x[row + col] *= y[row + col]

    @staticmethod 
    cdef inline void add_outer_i(weight_t* mat,
                                 const weight_t* x,
                                 const weight_t* y,
                                 int32_t nr_wide,
                                 int32_t nr_out) nogil:
        pass
