
#include <ngxe.h>

ngx_int_t ngxe_connection_bufsize;

void 
ngxe_connection_bufsize_init(ngx_int_t bufsize)
{
    ngxe_connection_bufsize = bufsize;
}

void
ngxe_dummy_handler(ngx_event_t *ev) 
{
    ngxe_debug("(%p) ngxe_dummy_handler", (ngx_connection_t *) ev->data);

    return;
}

void
ngxe_reader_handler(ngx_event_t *ev) 
{
    ngx_connection_t  *c;
    ngxe_session_t    *s;
    ngxe_callback_t   *cb;
    SV                *svbuf;
    u_char            *buf;
    ssize_t            n, cur, len;

    c = (ngx_connection_t *) ev->data;

    ngxe_debug("(%p) ngxe_reader_handler called", c);

    if (c == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): c == NULL");

	ngxe_debug("(%p) ngxe_reader_handler returned", c);
	return;
    }

    s = (ngxe_session_t *) c->data;
    if (s == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): s == NULL");

	ngxe_debug("(%p) ngxe_reader_handler returned", c);
	return;
    }

    cb = s->reader_callback;
    if (cb == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): cb == NULL");
	
	ngxe_debug("(%p) ngxe_reader_handler returned", c);
	return;
    }

    svbuf = s->reader_buffer;
    if (svbuf == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): svbuf == NULL");
	
	ngxe_debug("(%p) ngxe_reader_handler returned", c);
	return;
    }

    if (ev->timedout) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "client timed out");
	ngxe_debug("(%p) timedout", c);

	c->timedout = 1;

	sv_setiv(cb->args[1], -1); /* $error = -1 */
	sv_setpv(cb->args[1], "Operation timed out");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

	ngxe_close(c);
	
	ngxe_debug("(%p) ngxe_reader_handler returned", c);
	return;
    }

    if (c->read->timer_set) {
	ngxe_debug_timer("(%p) ngx_del_timer(c->read)", c);

	ngx_del_timer(c->read);
    }

RECVAGAIN:

    SvGROW(svbuf, ngxe_connection_bufsize);

    buf = (u_char *) SvPV_nolen(svbuf);
    cur = SvCUR(svbuf);
    len = SvLEN(svbuf);

/* XXX TODO
   SvGROW doesn't work properly here, using wrong malloc, probably because
   of the headers nginx includes,
   need fixing in nginx sources  */

    /* buffer already filled up */
    if (cur + 1 >= len) {
	goto CALLBACK; 
    }

    n = c->recv(c, buf + cur, len - cur - 1);

    if (n == NGX_ERROR || n == 0) {
	ngxe_debug("(%p) read error", c);

	sv_setiv(cb->args[1], 1); 
	sv_setpv(cb->args[1], "Read error");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

        ngxe_close(c);
        
	ngxe_debug("(%p) ngxe_reader_handler returned", c);
	return;
    }


    if (n > 0) {

	ngxe_debug("(%p) SvCUR_set(svbuf, %i)", c, cur + n);

	SvCUR_set(svbuf, cur + n);

	if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
	    ngxe_debug("(%p) event error", c);

	    sv_setiv(cb->args[1], -2); 
	    sv_setpv(cb->args[1], "Event error");
	    SvIOK_on(cb->args[1]);

	    ngxe_callback(cb, 1);

	    ngxe_close(c);
	    
	    ngxe_debug("(%p) ngxe_reader_handler returned", c);
	    return;
	}

	if (!c->read->timer_set && s->reader_timeout) {
	    ngxe_debug_timer("(%p) ngx_add_timer(c->read, %i)", 
			     c, s->reader_timeout);

	    ngx_add_timer(c->read, s->reader_timeout);
	}
    }

    if (n == NGX_AGAIN) {

	if (!c->read->timer_set && s->reader_timeout) {
	    ngxe_debug_timer("(%p) ngx_add_timer(c->read, %i)", 
			     c, s->reader_timeout);

	    ngx_add_timer(c->read, s->reader_timeout);
	}

	ngxe_debug("(%p) ngxe_reader_handler returned", c);
        return;
    }


    if (SvCUR(svbuf) + 1 < SvIV(cb->args[4]) && 
	SvCUR(svbuf) + 1 < SvLEN(svbuf)) 
    {
	/* not enough data for callback just yet */
	if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
	    ngxe_debug("(%p) event error", c);

	    sv_setiv(cb->args[1], -2); 
	    sv_setpv(cb->args[1], "Event error");
	    SvIOK_on(cb->args[1]);

	    ngxe_callback(cb, 1);

	    ngxe_close(c);
	    
	    ngxe_debug("(%p) ngxe_reader_handler returned", c);
	    return;
	}

	if (c->read->ready) {
	    goto RECVAGAIN;
	}

	if (!c->read->timer_set && s->reader_timeout) {
	    ngxe_debug_timer("(%p) ngx_add_timer(c->read, %i)", 
			     c, s->reader_timeout);

	    ngx_add_timer(c->read, s->reader_timeout);
	}

	ngxe_debug("(%p) ngxe_reader_handler returned", c);
	return; 
    } 

CALLBACK:
    ngxe_callback(cb, 0);

    if (!c->destroyed) {

	if (c->read->handler == ngxe_dummy_handler) {
	    /* just in case someone called ngxe_reader_stop */
	    ngxe_debug("(%p) ngxe_reader_handler returned", c);
	    return;
	}

	if (s->writer_callback != NULL && s->writer_buffer != NULL &&
	      (
	         SvROK(s->writer_buffer) || 
	         (SvPOK(s->writer_buffer) && SvCUR(s->writer_buffer) > 0)
	      )
	    )
	{
	    s->writer_offset = 0;
	    s->writer_index  = 0;

	    ngxe_reader_stop(c);
	    ngxe_writer_start(c);

	} else {

	    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
		ngxe_debug("(%p) ngx_handle_read_event error", c);

		sv_setiv(cb->args[1], -2); 
		sv_setpv(cb->args[1], "Event error");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);

		ngxe_debug("(%p) ngxe_reader_handler returned", c);
		return;
	    }

	    if (c->read->ready) {
		goto RECVAGAIN;
	    }
	    
	    if (!c->read->timer_set && s->reader_timeout) {
		ngxe_debug_timer("(%p) ngx_add_timer(c->read, %i)", 
				 c, s->reader_timeout);

		ngx_add_timer(c->read, s->reader_timeout);
	    }
	}

    }

    ngxe_debug("(%p) ngxe_reader_handler returned", c);
    return;
}


void
ngxe_reader_start(ngx_connection_t *c) 
{
    ngxe_session_t    *s;
    ngxe_callback_t   *cb;

    ngxe_debug("(%p) ngxe_reader_start", c);

    if (c == NULL) {
	ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
			"ngxe_reader_start() called on a NULL reference");
	return;
    }

    s = (ngxe_session_t *) c->data;
    cb = s->reader_callback;

    c->read->handler = ngxe_reader_handler;

    if (c->read->timer_set) {
	ngxe_debug_timer("(%p)     ngx_del_timer(c->read)", c);

	ngx_del_timer(c->read);
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
	ngxe_debug("(%p)     event error", c);

	sv_setiv(cb->args[1], -2); 
	sv_setpv(cb->args[1], "Event error");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

	ngxe_close(c);
	return;
    }

    if (!c->read->timer_set && s->reader_timeout) {
	ngxe_debug_timer("(%p)     ngx_add_timer(c->read, %i)", 
			 c, s->reader_timeout);

	ngx_add_timer(c->read, s->reader_timeout);
    }


/*
    if (c->read->ready) {
	c->read->handler(c->read);
    }
*/    
    return;
}


void
ngxe_reader_stop(ngx_connection_t *c) 
{
    ngxe_debug("(%p) ngxe_reader_stop", c);

    if (c == NULL) {
	ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
			"ngxe_reader_stop() called on a NULL reference");
	return;
    }

    if (c->read->timer_set) {
	ngxe_debug_timer("(%p)     ngx_del_timer(c->read)", c);

	ngx_del_timer(c->read);
    }

    c->read->handler = ngxe_dummy_handler;
    return;
}



void
ngxe_rvpv_writer_handler(ngx_event_t *ev) 
{
    ngx_connection_t  *c;
    ngxe_session_t    *s;
    ngxe_callback_t   *cb;
    SV                *svbuf;
    u_char            *buf;
    ssize_t            n, cur;

    c = (ngx_connection_t *) ev->data;
    s = (ngxe_session_t *) c->data;
    cb = s->writer_callback;
    svbuf = SvRV(s->writer_buffer);

    ngxe_debug("(%p) ngxe_rvpv_writer_handler", c);

    SvPOK_on(svbuf);

    if (ev->timedout) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "client timed out");

	c->timedout = 1;

	sv_setiv(cb->args[1], -1); 
	sv_setpv(cb->args[1], "Operation timed out");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

	ngxe_close(c);
	return;
    }

    if (c->write->timer_set) {
	ngx_del_timer(c->write);
    }

    cur = SvCUR(svbuf) - s->writer_offset;

    /* no data in buffer to send */ 
    if (cur <= 0) {

	s->writer_offset = 0;

	ngxe_callback(cb, 0);

	goto AFTERCALLBACK;
    }

SENDAGAIN:

    buf = (u_char *) SvPV_nolen(svbuf) + s->writer_offset;

    n = c->send(c, buf, cur);

    if (n == NGX_ERROR || n == 0) {

	s->writer_offset = 0;

	sv_setiv(cb->args[1], 1); 
	sv_setpv(cb->args[1], "Write error");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

        ngxe_close(c);
        return;
    }

    if (n > 0) {

	s->writer_offset += n;

	buf = (u_char *) SvPV_nolen(svbuf) + s->writer_offset;
	cur = SvCUR(svbuf) - s->writer_offset;

	if (cur > 0) {

	    c->write->ready = 0;
/*
	    if (c->write->ready) {
		goto SENDAGAIN;
	    }
*/

            if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

		s->writer_offset = 0;

		sv_setiv(cb->args[1], -2); 
		sv_setpv(cb->args[1], "Event error");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);
		return;
	    }

	    if (!c->write->timer_set && s->writer_timeout) {
		ngx_add_timer(c->write, s->writer_timeout);
	    }

	    return;

	} else if (cur <= 0) {

	    s->writer_offset = 0;
	}

    }

    if (n == NGX_AGAIN) {

	if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

	    s->writer_offset = 0;

	    sv_setiv(cb->args[1], -2); 
	    sv_setpv(cb->args[1], "Event error");
	    SvIOK_on(cb->args[1]);

	    ngxe_callback(cb, 1);

	    ngxe_close(c);
	    return;
	}

	if (c->write->ready) {
	    goto SENDAGAIN;
	}

	if (!c->write->timer_set && s->writer_timeout) {
	    ngx_add_timer(c->write, s->writer_timeout);
	}

        return;
 
    }

    /* $_[3] = undef,  */
    SvREFCNT_dec(SvRV(s->writer_buffer));
    SvRV_set(s->writer_buffer, &PL_sv_undef); 
    SvSetSV(s->writer_buffer, &PL_sv_undef); 

    ngxe_callback(cb, 0);


AFTERCALLBACK:

    /* ngxe_closed was not called() */
    if (!c->destroyed) {

	if (c->write->handler == ngxe_dummy_handler) {
	    /* just in case someone called ngxe_writer_stop */
	    return;
	}

	if (SvOK(s->writer_buffer) && SvROK(s->writer_buffer) && 
	    SvCUR(SvRV(s->writer_buffer)) > 0) {

	    /* this thing requires to work with scalar refs only
	       need to be rewritten someday */

            svbuf = SvRV(s->writer_buffer);
	    cur = SvCUR(svbuf) - s->writer_offset;

	    if (c->write->ready) {
		goto SENDAGAIN; 
	    }

	    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

		s->writer_offset = 0;

		sv_setiv(cb->args[1], -2); 
		sv_setpv(cb->args[1], "Event error");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);
		return;
	    }

	    if (!c->write->timer_set && s->writer_timeout) {
		ngx_add_timer(c->write, s->writer_timeout);
	    }


	} else {

	    /* restarting reader if no data has been added to the 
	       writer's buffer and connection was not destroyed.  
	       You kind of have to choose to either add new data
	       to the buffer and continue sending it or do nothing
	       and restart the reader. Or you can just close connection
	       and be free.
	       */

	    if (s->reader_callback != NULL && s->reader_buffer != NULL) {

                ngxe_writer_stop(c);
		ngxe_reader_start(c);
	    }
	}
    }

    return;
}



void
ngxe_rvpvav_writer_handler(ngx_event_t *ev) 
{
    ngx_connection_t  *c;
    ngxe_session_t    *s;
    ngxe_callback_t   *cb;
    SV                *svbuf;
    u_char            *buf;
    ssize_t            n, cur;
    I32                avlen;

    c = (ngx_connection_t *) ev->data;
    s = (ngxe_session_t *) c->data;
    cb = s->writer_callback;

    ngxe_debug("(%p) ngxe_rvpvav_writer_handler", c);

    if (ev->timedout) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "client timed out");

	c->timedout = 1;

	sv_setiv(cb->args[1], -1); 
	sv_setpv(cb->args[1], "Operation timed out");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

	ngxe_close(c);
	return;
    }

    if (c->write->timer_set) {
	ngx_del_timer(c->write);
    }



NEXTBUF:

    avlen = av_len((AV *)SvRV(s->writer_buffer));

    if (s->writer_index > avlen) { 
	goto DONE;
    }

    svbuf = *av_fetch((AV *)SvRV(s->writer_buffer), s->writer_index, 0);

    if (!SvOK(svbuf) || !SvROK(svbuf)) {

	s->writer_offset = 0;
	s->writer_index  = 0;

	sv_setiv(cb->args[1], 1); 
	sv_setpv(cb->args[1], "Buffer is not a SCALAR REF");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

        ngxe_close(c);
        return;
    }

    svbuf = SvRV(svbuf);

    SvPOK_on(svbuf);

    cur = SvCUR(svbuf) - s->writer_offset;

    /* no data in buffer to send */ 
    if (cur <= 0) {

	s->writer_offset = 0;
	s->writer_index++;

	goto NEXTBUF;
    }

SENDAGAIN:

    buf = (u_char *) SvPV_nolen(svbuf) + s->writer_offset;

    n = c->send(c, buf, cur);

    if (n == NGX_ERROR || n == 0) {

	s->writer_offset = 0;
	s->writer_index  = 0;

	sv_setiv(cb->args[1], 1); 
	sv_setpv(cb->args[1], "Write error");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

        ngxe_close(c);
        return;
    }

    if (n > 0) {

	s->writer_offset += n;

	buf = (u_char *) SvPV_nolen(svbuf) + s->writer_offset;
	cur = SvCUR(svbuf) - s->writer_offset;

	if (c->write->timer_set) {
	    ngx_del_timer(c->write);
	}

	if (cur > 0) {

	    c->write->ready = 0;
/*
	    if (c->write->ready) {
		goto SENDAGAIN;
	    }
*/

            if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

		s->writer_offset = 0;

		sv_setiv(cb->args[1], -2); 
		sv_setpv(cb->args[1], "Event error");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);
		return;
	    }

	    if (!c->write->timer_set && s->writer_timeout) {
		ngx_add_timer(c->write, s->writer_timeout);
	    }

	    return;

	} else if (cur <= 0) {

	    s->writer_offset = 0;
	    s->writer_index++;

	    goto NEXTBUF;
	}
    }

    if (n == NGX_AGAIN) {

	if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

	    s->writer_offset = 0;

	    sv_setiv(cb->args[1], -2); 
	    sv_setpv(cb->args[1], "Event error");
	    SvIOK_on(cb->args[1]);

	    ngxe_callback(cb, 1);

	    ngxe_close(c);
	    return;
	}

	if (c->write->ready) {
	    goto SENDAGAIN;
	}

	if (!c->write->timer_set && s->writer_timeout) {
	    ngx_add_timer(c->write, s->writer_timeout);
	}

        return;
    }

DONE:

    /* $_[3] = undef */
    SvREFCNT_dec(SvRV(s->writer_buffer));
    SvRV_set(s->writer_buffer, &PL_sv_undef); 
    SvSetSV(s->writer_buffer, &PL_sv_undef); 

    ngxe_callback(cb, 0);

    /* ngxe_closed was not called() */
    if (!c->destroyed) {

	if (c->write->handler == ngxe_dummy_handler) {
	    /* just in case someone called ngxe_writer_stop */
	    return;
	}

	if (SvOK(s->writer_buffer) && SvROK(s->writer_buffer)) {

	    /* XXX expects another buffer of the same type
	       won't work with other types */

	    s->writer_offset = 0;
	    s->writer_index  = 0;

	    if (c->write->ready) {
		goto NEXTBUF; 
	    }

	    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

		s->writer_offset = 0;

		sv_setiv(cb->args[1], -2); 
		sv_setpv(cb->args[1], "Event error");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);
		return;
	    }

	    if (!c->write->timer_set && s->writer_timeout) {
		ngx_add_timer(c->write, s->writer_timeout);
	    }

	    return;

	} else {

	    /* restarting reader if no data has been added to the 
	       writer's buffer and connection was not destroyed.  
	       You kind of have to choose to either add new data
	       to the buffer and continue sending it or do nothing
	       and restart the reader. Or you can just close connection
	       and be free.
	       */

	    if (s->reader_callback != NULL && s->reader_buffer != NULL) {

                ngxe_writer_stop(c);
		ngxe_reader_start(c);
	    }
	}
    }

    return;
}






void
ngxe_writer_handler(ngx_event_t *ev) 
{
    ngx_connection_t  *c;
    ngxe_session_t    *s;
    ngxe_callback_t   *cb;
    SV                *svbuf;
    u_char            *buf;
    ssize_t            n, cur;

    c = (ngx_connection_t *) ev->data;

    ngxe_debug("(%p) ngxe_writer_handler", c);

    if (c == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): c == NULL");
	return;
    }

    s = (ngxe_session_t *) c->data;
    if (s == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): s == NULL");
	return;
    }

    cb = s->writer_callback;
    if (cb == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): cb == NULL");
	return;
    }

    svbuf = s->writer_buffer;
    if (svbuf == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_reader_handler(): svbuf == NULL");
	return;
    }

    if (SvROK(s->writer_buffer)) {

	if (SvTYPE(SvRV(s->writer_buffer)) == SVt_PV) {

	    ngxe_rvpv_writer_handler(ev);
	    return;

	} else if (SvTYPE(SvRV(s->writer_buffer)) == SVt_PVAV) {

	    ngxe_rvpvav_writer_handler(ev);
	    return;

	} else {

	    sv_setiv(cb->args[1], 1); 
	    sv_setpv(cb->args[1], "Unsupported buffer type");
	    SvIOK_on(cb->args[1]);

	    ngxe_callback(cb, 1);

	    ngxe_close(c);
	    return;
	}
    }


    if (ev->timedout) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "client timed out");

	c->timedout = 1;

	sv_setiv(cb->args[1], -1); 
	sv_setpv(cb->args[1], "Operation timed out");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

	ngxe_close(c);
	return;
    }

    if (c->write->timer_set) {
	ngx_del_timer(c->write);
    }

    cur = SvCUR(svbuf);

    /* no data in buffer to send */ 
    if (cur == 0) {

	ngxe_callback(cb, 0);

	goto AFTERCALLBACK;
    }

SENDAGAIN:

    buf = (u_char *) SvPV_nolen(svbuf);

    n = c->send(c, buf, cur);

    if (n == NGX_ERROR || n == 0) {

	sv_setiv(cb->args[1], 1); 
	sv_setpv(cb->args[1], "Write error");
	SvIOK_on(cb->args[1]);

	ngxe_callback(cb, 1);

        ngxe_close(c);
        return;
    }

    if (n > 0) {

	sv_chop(svbuf, (char *)buf + n);

	buf = (u_char *) SvPV_nolen(svbuf);
	cur = SvCUR(svbuf);

	if (cur > 0) {

	    c->write->ready = 0;
/*
	    if (c->write->ready) {
		goto SENDAGAIN;
	    }
*/

            if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

		sv_setiv(cb->args[1], -2); 
		sv_setpv(cb->args[1], "Event error");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);
		return;
	    }

	    if (!c->write->timer_set && s->writer_timeout) {
		ngx_add_timer(c->write, s->writer_timeout);
	    }

	    return;

	} else if (cur == 0) {

	    SvOOK_off(svbuf);
	    SvCUR_set(svbuf, 0);
	}
    }

    if (n == NGX_AGAIN) {

	if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

	    sv_setiv(cb->args[1], -2); 
	    sv_setpv(cb->args[1], "Event error");
	    SvIOK_on(cb->args[1]);

	    ngxe_callback(cb, 1);

	    ngxe_close(c);
	    return;
	}

	if (c->write->ready) {
	    goto SENDAGAIN;
	}

	if (!c->write->timer_set && s->writer_timeout) {
	    ngx_add_timer(c->write, s->writer_timeout);
	}

        return;
    }

    ngxe_callback(cb, 0);


AFTERCALLBACK:

    /* ngxe_closed was not called() */
    if (!c->destroyed) {

	if (c->write->handler == ngxe_dummy_handler) {
	    /* just in case someone called ngxe_writer_stop */
	    return;
	}

	cur = SvCUR(svbuf);

	if (cur > 0) {

	    if (c->write->ready) {
		goto SENDAGAIN; 
	    }

	    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {

		sv_setiv(cb->args[1], -2); 
		sv_setpv(cb->args[1], "Event error");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);
		return;
	    }

	    if (!c->write->timer_set && s->writer_timeout) {
		ngx_add_timer(c->write, s->writer_timeout);
	    }


	} else {

	    /* restarting reader if no data has been added to the 
	       writer's buffer and connection was not destroyed.  
	       You kind of have to choose to either add new data
	       to the buffer and continue sending it or do nothing
	       and restart the reader. Or you can just close connection
	       and be free.
	       */

	    if (s->reader_callback != NULL && s->reader_buffer != NULL) {

                ngxe_writer_stop(c);
		ngxe_reader_start(c);
	    }
	}
    }

    return;
}




void
ngxe_writer_start(ngx_connection_t *c) 
{
    ngxe_session_t    *s;
    ngxe_callback_t   *cb;

    ngxe_debug("(%p) ngxe_writer_start", c);

    if (c == NULL) {
	ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
			"ngxe_writer_start() called on a NULL reference");
	return;
    }

    s = (ngxe_session_t *) c->data;
    cb = s->writer_callback;

    c->write->handler = ngxe_writer_handler;

    if (c->write->timer_set) {
	ngxe_debug_timer("(%p) ngx_del_timer(c->write)", c); 

	ngx_del_timer(c->write);
    }

    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
	ngxe_debug("(%p) event error", c);

	sv_setiv(cb->args[1], -2); 
	sv_setpv(cb->args[1], "Event error");
	SvIOK_on(cb->args[1]);

        ngxe_callback(cb, 1);

	ngxe_close(c);
	return;
    }

    if (!c->write->timer_set && s->writer_timeout) {
	ngxe_debug_timer("(%p) ngx_add_timer(c->write, %i)", 
			  c, s->writer_timeout);

	ngx_add_timer(c->write, s->writer_timeout);
    }

    if (c->write->ready) {
	ngxe_debug("(%p) c->write->handler(c->write)", c); 

	c->write->handler(c->write); 
    }
    
    return;
}


void
ngxe_writer_stop(ngx_connection_t *c) 
{

    ngxe_debug("(%p) ngxe_writer_stop", c);

    if (c == NULL) {
	ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
			"ngxe_writer_stop() called on a NULL reference");
	return;
    }

    if (c->write->timer_set) {
	ngxe_debug_timer("(%p) ngx_del_timer(c->write)", c); 

	ngx_del_timer(c->write);
    }

    c->write->handler = ngxe_dummy_handler;

    return;
}












void
ngxe_close(ngx_connection_t *c) 
{
    ngx_pool_t       *pool;

    ngxe_debug("(%p) ngxe_close", c);

    if (c == NULL) {
	ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
			"ngxe_close() called on a NULL reference");
	return;
    }

    if (c->destroyed) {
	ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
			"ngxe_close() called on destroyed connection");
	return;
    }

    c->destroyed = 1;

    pool = c->pool;
    ngx_close_connection(c);
    ngx_destroy_pool(pool);

    return;
}



void
ngxe_client_init_handler(ngx_event_t *ev)
{
    ngx_connection_t  *c;
    ngxe_session_t    *s;
    ngxe_callback_t   *cb;

    c = (ngx_connection_t *) ev->data;

    ngxe_debug("(%p) ngxe_client_init_handler", c);

    if (c == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_client_init_handler(): c == NULL");
	return;
    }

    c->read->handler = ngxe_dummy_handler;
    c->write->handler = ngxe_dummy_handler;

    s = (ngxe_session_t *) c->data;
    if (s == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_client_init_handler(): s == NULL");
	return;
    }

    cb = s->writer_callback;
    if (cb == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, 
			    "ngxe_client_init_handler(): cb == NULL");
	return;
    }


    if (ev->error) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "client error");

	sv_setiv(cb->args[1], -1); 
	sv_setpv(cb->args[1], "Connect error");
	SvIOK_on(cb->args[1]);
	ngxe_callback(cb, 1);

	ngxe_close(c);
	return;
    }


    if (ev->timedout) {
        ngx_log_error(NGX_LOG_INFO, c->log, NGX_ETIMEDOUT, "client timed out");

	c->timedout = 1;

	sv_setiv(cb->args[1], -1); 
	sv_setpv(cb->args[1], "Operation timed out");
	SvIOK_on(cb->args[1]);
	ngxe_callback(cb, 1);

	ngxe_close(c);
	return;
    }

    if (c->write->timer_set) {
	ngx_del_timer(c->write);
    }

    ngxe_callback(cb, 1);
    return;
}





ngx_peer_connection_t *
ngxe_create_peer(ngx_pool_t *pool, in_addr_t bindaddr, in_addr_t addr, 
    in_port_t port)
{
    ngx_addr_t             *local;
    struct sockaddr_in     *sin, *localsin;
    ngx_log_t              *log;
    ngx_peer_connection_t  *peer;

    log = pool->log;

    local = ngx_pcalloc(pool, sizeof(ngx_addr_t));
    if (local == NULL) {
	ngx_log_error(NGX_LOG_ERR, log, 0, 
			"local = ngx_pcalloc(pool, sizeof(ngx_addr_t)) "
			"failed");
	return NULL;
    }

    localsin = ngx_pcalloc(pool, sizeof(struct sockaddr_in));
    if (localsin == NULL) {
	ngx_log_error(NGX_LOG_ERR, log, 0, 
			"localsin = ngx_pcalloc(pool, "
			    "sizeof(struct sockaddr_in)) "
			"failed");
	return NULL;
    }

    localsin->sin_family = AF_INET;
    localsin->sin_addr.s_addr = addr;
    local->sockaddr = (struct sockaddr *) localsin;
    local->socklen = sizeof(struct sockaddr_in);


    sin = ngx_pcalloc(pool, sizeof(struct sockaddr_in));
    if (sin == NULL) {
	ngx_log_error(NGX_LOG_ERR, log, 0, 
			"sin = ngx_pcalloc(pool, sizeof(struct sockaddr_in)) "
			"failed");
	return NULL;
    }

    sin->sin_family = AF_INET;
    sin->sin_addr.s_addr = addr;
    sin->sin_port = htons((in_port_t) port);

    peer = ngx_pcalloc(pool, sizeof(ngx_peer_connection_t));
    if (peer == NULL) {
	ngx_log_error(NGX_LOG_ERR, log, 0, 
			"peer = ngx_pcalloc(pool, "
				    "sizeof(ngx_peer_connection_t)) "
			"failed");
	return NULL;
    }


    peer->sockaddr = (struct sockaddr *) sin;
    peer->socklen = sizeof(struct sockaddr_in);
    peer->get = ngx_event_get_peer;
    peer->log = log;
    peer->log_error = NGX_ERROR_ERR;

    peer->name = ngx_pcalloc(pool, sizeof(ngx_str_t));
    if (peer->name == NULL) {
	ngx_log_error(NGX_LOG_ERR, log, 0, 
			"peer->name = ngx_pcalloc(pool, sizeof(ngx_str_t *)); "
			"failed");
	return NULL;
    }

    return peer;
}




static void
ngxe_server_init_connection(ngx_connection_t *c)
{
    ngxe_session_t      *s;
    ngxe_callback_t     *cb;
    ngx_log_t           *log;

    log = ngx_cycle->log;
    c->log = log;

    ngxe_debug("(%p) ngxe_server_init_connection", c);

    s = ngx_pcalloc(c->pool, sizeof(ngxe_session_t));
    if (s == NULL) {
	ngx_log_error(NGX_LOG_ERR, log, 0, 
			"s = ngx_pcalloc(c->pool, sizeof(ngxe_session_t)) "
			"failed");
	ngxe_close(c);
	return;
    }

    c->data = (void *) s;

    c->read->handler = ngxe_dummy_handler;
    c->write->handler = ngxe_dummy_handler;

    cb = (ngxe_callback_t *) c->listening->connection->data;

    sv_setiv(cb->args[0], PTR2IV(c));
    sv_setpvn(cb->args[1], (const char *) c->addr_text.data, c->addr_text.len);

    ngxe_callback(cb, 0);

    return;
}




ngx_listening_t *
ngxe_server_create(ngx_cycle_t *cycle, in_addr_t addr, in_port_t port)
{
    ngx_listening_t       *ls;
    struct sockaddr_in    *sin;
    ngx_pool_t            *pool;

    pool = ngx_create_pool(256, cycle->log);
    if (pool == NULL) {
	ngx_log_error(NGX_LOG_ERR, cycle->log, 0, 
			"ngx_create_pool(256, cycle->log) "
			"returned NULL");
	return NULL;
    }

    sin = ngx_pcalloc(pool, sizeof(struct sockaddr_in));
    if (sin == NULL) {
	ngx_log_error(NGX_LOG_ERR, cycle->log, 0, 
			"ngx_pcalloc(pool, sizeof(struct sockaddr_in)) "
			"returned NULL");
	return NULL;
    }

    sin->sin_family = AF_INET;
    sin->sin_addr.s_addr = addr;
    sin->sin_port = htons((in_port_t) port);

    ls = ngx_ngxe_create_listening(pool, sin, sizeof(struct sockaddr_in));
    if (ls == NULL) {
	ngx_log_error(NGX_LOG_ERR, cycle->log, 0, 
			"ngx_ngxe_create_listening(pool, sin, "
			    "sizeof(struct sockaddr_in)) "
			"returned NULL");
	return NULL;
    }

    ls->handler = ngxe_server_init_connection;
    ls->pool_size = 256;
    ls->addr_ntop = 1;
    ls->logp = cycle->log;
    ls->log = *cycle->log;

/*
    ls->log.data = &ls->addr_text;
    ls->log.handler = ngx_accept_log_error;
*/
    ngx_ngxe_open_listening_socket(ls);

    if (ngx_ngxe_add_listening_connection(ls) != NGX_OK) {
	ngx_log_error(NGX_LOG_ERR, cycle->log, 0, 
			"ngx_ngxe_add_listening_connection(ls) "
			"failed");
	return NULL;
    }

    ls->connection->pool = pool;
    ls->connection->log = cycle->log;

    return ls;
}



