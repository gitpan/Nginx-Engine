
#include <ngxe.h>


void
ngxe_callback_dec(ngxe_callback_t *cb)
{
    int i;
#ifdef NGXE_DEBUG
    ngx_connection_t *c;

    c = NULL;
#endif

#ifdef NGXE_DEBUG
    if (!cb->decremented) {
        c = INT2PTR(ngx_connection_t *, SvIV(cb->args[0]));
    }
#endif

    ngxe_debug("(%p) ngxe_callback_dec called", c);

    if (cb->decremented == 0) {

	if (cb->handler != NULL) {
#ifdef NGXE_DEBUG_CBARGS
	    ngxe_debug("(%p) ngxe_callback_dec: SvREFCNT_dec(cb->handler)", c);
#endif
	    SvREFCNT_dec(cb->handler);
	}

	for (i = 0; i < cb->args_n; i++) {
#ifdef NGXE_DEBUG_CBARGS
	    ngxe_debug("(%p) ngxe_callback_dec: SvREFCNT_dec(cb->args[%i])", c, i);
#endif
	    SvREFCNT_dec(cb->args[i]);
	}

	cb->args_n = 0;
	cb->decremented = 1;
    }

    ngxe_debug("(%p) ngxe_callback_dec returned", c);
    return;
}



void 
ngxe_callback(ngxe_callback_t *cb, char decrefcnts)
{
    int i, n;
    ngx_connection_t *c;
    dSP;

    c = INT2PTR(ngx_connection_t *, SvIV(cb->args[0]));

    ngxe_debug("(%p) ngxe_callback called", c);

    if (cb->handler == NULL) {
        ngxe_debug("(%p) ngxe_callback: no perl handler found", c);

	if (cb->native_handler != NULL) {
	    ngxe_debug("(%p) ngxe_callback: native handler found", c);

	    cb->native_handler(c);
	} else {
	    ngxe_debug("(%p) ngxe_callback: no native handler found", c);
	}

        ngxe_debug("(%p) ngxe_callback returned", c);
	return;
    }


    n = cb->args_n;

    ENTER;
    SAVETMPS; 

    PUSHMARK(SP);
    EXTEND(SP, cb->args_n);

#ifdef NGXE_DEBUG_CBARGS
    ngxe_debug("(%p) ngxe_callback: SvREFCNT_inc(cb->handler)", c);
#endif
    SvREFCNT_inc(cb->handler);

    for (i = 0; i < cb->args_n; i++) {
#ifdef NGXE_DEBUG_CBARGS
	ngxe_debug("(%p) ngxe_callback: SvREFCNT_inc(cb->args[%i])", c, i);
#endif
	SvREFCNT_inc(cb->args[i]);
	PUSHs(cb->args[i]);
    }
    PUTBACK;

    call_sv(cb->handler, G_VOID|G_DISCARD);

    for (i = 0; i < n; i++) { /* XXX args_n may have already 
				    been reset to 0, using n instead */
#ifdef NGXE_DEBUG_CBARGS
	ngxe_debug("(%p) ngxe_callback: SvREFCNT_dec(cb->args[%i])", c, i);
#endif
        SvREFCNT_dec(cb->args[i]);
    }
#ifdef NGXE_DEBUG_CBARGS
    ngxe_debug("(%p) ngxe_callback: SvREFCNT_dec(cb->handler)", c);
#endif
    SvREFCNT_dec(cb->handler);

    if (decrefcnts) {
	if (cb->decremented == 0) {
	    if (cb->handler != NULL) {
#ifdef NGXE_DEBUG_CBARGS
		ngxe_debug("(%p) ngxe_callback: SvREFCNT_dec(cb->handler)", c);
#endif
		SvREFCNT_dec(cb->handler);
	    }

	    for (i = 0; i < cb->args_n; i++) {
#ifdef NGXE_DEBUG_CBARGS
		ngxe_debug("(%p) ngxe_callback: SvREFCNT_dec(cb->args[%i])", c, i);
#endif
		SvREFCNT_dec(cb->args[i]);
	    }

	    cb->args_n = 0;
	    cb->decremented = 1;
	}
    }

    FREETMPS; 
    LEAVE;

    ngxe_debug("(%p) ngxe_callback returned", c);
    return;
}


void 
ngxe_callback_cleanup(void *data)
{
    ngxe_callback_t  *cb;
#ifdef NGXE_DEBUG
    ngx_connection_t *c;

    c = NULL;
#endif

    cb = (ngxe_callback_t *) data;

#ifdef NGXE_DEBUG
    if (!cb->decremented) {
        c = INT2PTR(ngx_connection_t *, SvIV(cb->args[0]));
    }
#endif

    ngxe_debug("(%p) ngxe_callback_cleanup called", c);

    if (cb->decremented == 0) {
	ngxe_callback_dec(cb);
    }

    ngxe_debug("(%p) ngxe_callback_cleanup returned", c);
    return;
}

