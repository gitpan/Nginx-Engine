
#include <ngxe.h>


void
ngxe_callback_dec(ngxe_callback_t *cb)
{
    int i;

    if (cb->decremented == 0) {
	if (cb->handler != NULL) {
	    SvREFCNT_dec(cb->handler);
	}

	for (i = 0; i < cb->args_n; i++) {
	    SvREFCNT_dec(cb->args[i]);
	}

	cb->args_n = 0;
	cb->decremented = 1;
    }

    return;
}


void 
ngxe_connection_buffer_callback(ngxe_callback_t *cb, ngx_connection_t *c, 
    SV *buffer)
{
	int i;
	dSP;

	ENTER;
	SAVETMPS; 

	PUSHMARK(SP);
	EXTEND(SP, cb->args_n + 1);
	sv_setiv(cb->args[0], PTR2IV(c)); /* changing first arg */
	PUSHs(cb->args[0]);
	PUSHs(buffer);
        for (i = 1; i < cb->args_n; i++) {
		PUSHs(cb->args[i]);
	}
	PUTBACK;

	call_sv(cb->handler, G_VOID|G_DISCARD);

	FREETMPS; 
	LEAVE;

	return;
}




void 
ngxe_connection_callback(ngxe_callback_t *cb, ngx_connection_t *c, 
    char decrefcnts)
{
	int i;
	dSP;

	ENTER;
	SAVETMPS; 

	PUSHMARK(SP);
	EXTEND(SP, cb->args_n);
	sv_setiv(cb->args[0], PTR2IV(c)); /* changing first arg */
        for (i = 0; i < cb->args_n; i++) {
		PUSHs(cb->args[i]);
	}
	PUTBACK;

	call_sv(cb->handler, G_VOID|G_DISCARD);

	if (decrefcnts) {
	    if (cb->decremented == 0) {
		SvREFCNT_dec(cb->handler);
		for (i = 0; i < cb->args_n; i++) {
			SvREFCNT_dec(cb->args[i]);
		}

		cb->args_n = 0;
		cb->decremented = 1;
	    }
	}

	FREETMPS; 
	LEAVE;

	return;
}



void 
ngxe_callback(ngxe_callback_t *cb, char decrefcnts)
{
    int i;
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


    ENTER;
    SAVETMPS; 

    PUSHMARK(SP);
    EXTEND(SP, cb->args_n);
    for (i = 0; i < cb->args_n; i++) {
	    PUSHs(cb->args[i]);
    }
    PUTBACK;

    call_sv(cb->handler, G_VOID|G_DISCARD);

    if (decrefcnts) {
	if (cb->decremented == 0) {
	    if (cb->handler != NULL) {
		SvREFCNT_dec(cb->handler);
	    }

	    for (i = 0; i < cb->args_n; i++) {
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

    ngxe_debug("(%p) ngxe_callback_cleanup", c);

    if (cb->decremented == 0) {
	ngxe_callback_dec(cb);
    }

    return;
}

