
#include <ngxe.h>


void
ngxe_callback_dec(ngxe_callback_t *cb)
{
    int i;

    if (cb->decremented == 0) {
	SvREFCNT_dec(cb->handler);
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
	dSP;

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
ngxe_callback_cleanup(void *data)
{
    ngxe_callback_t  *cb;

    cb = (ngxe_callback_t *) data;

    if (cb->handler == NULL) {
	/* not using perl handler -- no point to cleanup */
	return;
    }

    if (cb->decremented == 0) {
	ngxe_callback_dec(cb);
    }

    return;
}

