
#include <ngxe.h>

static ngxe_bufs_t  ngxe_bufs;

void
ngxe_bufs_init(ngx_int_t svlen) 
{
    ngxe_bufs.svlen = svlen;

    ngxe_debug("ngxe_bufs_init %i", svlen);

    return;
}


SV *
ngxe_buf()
{
    ngx_int_t     i;
    ngxe_buf_t   *buf;

    /* not enough buffer structures, allocating 1024 */
    if (ngxe_bufs.free_buf == NULL) {
        ngxe_debug("ngxe_buf: allocating 64 new buffers");

	Newx(buf, 1024, ngxe_buf_t);
	if (buf == NULL) {
	    return NULL;
	}
	ZeroD(buf, 1024, ngxe_buf_t);

	for (i = 0; i < 1024; i++) {
	    buf[i].next_buf = ngxe_bufs.free_buf;
	    ngxe_bufs.free_buf = &buf[i];
	    ngxe_bufs.free_bufs_n++;
	}
    }

    buf = ngxe_bufs.free_buf;

    ngxe_bufs.free_buf = buf->next_buf;
    ngxe_bufs.free_bufs_n--;

    buf->next_buf = ngxe_bufs.inuse_buf;
    ngxe_bufs.inuse_buf = buf;
    ngxe_bufs.inuse_bufs_n++;

    if (buf->sv == NULL) {
        ngxe_debug("ngxe_buf: newSV");

	buf->sv = newSV(ngxe_bufs.svlen);
	SvREFCNT_inc(buf->sv); /* it should never be destroyed */
	SvPOK_only(buf->sv);
	SvCUR_set(buf->sv, 0);
    } else {
        ngxe_debug("ngxe_buf: reusing sv");

	SvPOK_on(buf->sv);
	SvCUR_set(buf->sv, 0);
    }

    ngxe_debug("ngxe_bufs: %i %i", ngxe_bufs.inuse_bufs_n, 
				   ngxe_bufs.free_bufs_n);

    return buf->sv;
}


void 
ngxe_buffree(SV *sv)
{
    ngxe_buf_t   *buf;

    buf = ngxe_bufs.inuse_buf;
    if (buf == NULL) {
	warn("Buffer was not allocated\n");
	return;
    }

    buf->sv = sv;

    ngxe_bufs.inuse_buf = buf->next_buf;
    ngxe_bufs.inuse_bufs_n--;

    buf->next_buf = ngxe_bufs.free_buf;
    ngxe_bufs.free_buf = buf;
    ngxe_bufs.free_bufs_n++;
    
    ngxe_debug("ngxe_buffree: releasing buffer");
    ngxe_debug("ngxe_bufs: %i %i", ngxe_bufs.inuse_bufs_n, 
				   ngxe_bufs.free_bufs_n);
}


void 
ngxe_buf_cleanup(void *data)
{
    SV  *sv;

    sv = (SV *) data;

    ngxe_debug("(-1) ngxe_buf_cleanup %p", sv);

    ngxe_buffree(sv);

    return;
}

