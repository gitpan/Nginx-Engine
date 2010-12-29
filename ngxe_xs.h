
#ifndef _NGXE_XS_H_INCLUDED_
#define _NGXE_XS_H_INCLUDED_

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <ngxe_ngx.h>

typedef struct {
/* perl callback */
    SV    *handler;
    SV   **args;
    int    args_n;
    int    decremented;

/* native callback */
    ngx_connection_handler_pt connection_handler;
} ngxe_callback_t;

void ngxe_callback_dec(ngxe_callback_t *cb);
void ngxe_connection_callback(ngxe_callback_t *cb, ngx_connection_t *c, 
	char decrefcnts);
void ngxe_connection_buffer_callback(ngxe_callback_t *cb, ngx_connection_t *c, 
	SV *buffer);
void ngxe_callback(ngxe_callback_t *cb, char decrefcnts);

void ngxe_callback_cleanup(void *data);

#endif /* _NGXE_XS_H_INCLUDED_ */

