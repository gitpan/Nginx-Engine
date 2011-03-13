
#ifndef _NGXE_BUFS_H_INCLUDED_
#define _NGXE_BUFS_H_INCLUDED_

#include <ngxe_ngx.h>

typedef struct ngxe_buf_s ngxe_buf_t;
struct ngxe_buf_s {
    ngxe_buf_t  *next_buf;
    SV          *sv;
};

typedef struct {
    ngxe_buf_t    *free_buf;
    ngx_int_t      free_bufs_n;
    ngxe_buf_t    *inuse_buf;
    ngx_int_t      inuse_bufs_n;
    size_t         svlen;
} ngxe_bufs_t;

void   ngxe_bufs_init(ngx_int_t svlen);
SV    *ngxe_buf();
void   ngxe_buffree(SV *sv);
void   ngxe_buf_cleanup(void *data);

#define NGXE_READER_USE_BUFS 

#endif /* _NGXE_BUFS_H_INCLUDED_ */


