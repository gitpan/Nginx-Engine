
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

int  ngxe_pagesize;

/* #define NGXE_READER_USE_BUFS */




#define ngxe_buf_newsv(s) ( \
	s <=     4080 ? newSV(    4080) : \
	s <=    32768 ? newSV(   32768 + ngxe_pagesize - 16) : \
	s <=   262144 ? newSV(  262144 + ngxe_pagesize - 16) : \
	s <=  1048576 ? newSV( 1048576 + ngxe_pagesize - 16) : \
	s <=  4194304 ? newSV( 4194304) : \
	newSV(s) \
)

#define ngxe_buf_svgrow(sv,s) ( \
	s <=     4080 ? SvGROW(sv,     4080) : \
	s <=    32768 ? SvGROW(sv,    32768 + ngxe_pagesize - 16) : \
	s <=   262144 ? SvGROW(sv,   262144 + ngxe_pagesize - 16) : \
	s <=  1048576 ? SvGROW(sv,  1048576 + ngxe_pagesize - 16) : \
	s <=  4194304 ? SvGROW(sv,  4194304) : \
	SvGROW(sv, s) \
)



#endif /* _NGXE_BUFS_H_INCLUDED_ */


