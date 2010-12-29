
#include <ngxe.h>

MODULE = Nginx::Engine		PACKAGE = Nginx::Engine		




SV *
ngxe_interval_set(msec, sub, ...)
	int msec
	SV *sub
    CODE:
	ngx_connection_t  *c;
	ngxe_interval_t   *interval;
	ngxe_callback_t   *cb;
	int               i;

	c = ngx_get_connection((ngx_socket_t) 0, ngx_cycle->log);
	if (c == NULL) {
		XSRETURN_UNDEF;
	}
	
	c->read->handler = ngxe_interval_callback;
	c->read->active = 1;
	c->read->log = ngx_cycle->log;
	c->pool = ngx_create_pool(128, ngx_cycle->log);
	
	interval = ngx_pcalloc(c->pool, sizeof(ngxe_interval_t));
	if (interval == NULL) {
		XSRETURN_UNDEF;
	}
	
	c->data = (void *) interval;

	interval->connection = c;
	interval->msec = msec;

	cb = ngx_pcalloc(c->pool, sizeof(ngxe_callback_t));
	if (cb == NULL) {
		XSRETURN_UNDEF;
	}
	
	interval->callback = cb;

	/* creating perl callback */

	cb->handler = sv_2mortal(newSVsv(sub));
	SvREFCNT_inc(cb->handler); 

	cb->args_n = (items - 2) + 1; 
	if (cb->args_n > 0) {
	    cb->args = ngx_pcalloc(c->pool, cb->args_n * sizeof(SV *));
	}

	cb->args[0] = sv_2mortal(newSViv(PTR2IV(interval)));
	SvREFCNT_inc(cb->args[0]);

	for (i = 1; i < cb->args_n; i++) {
	    cb->args[i] = sv_2mortal(newSVsv(ST((i+2)-1)));
	    SvREFCNT_inc(cb->args[i]);
	}

	/* */

	ngx_event_add_timer(c->read, msec);

	RETVAL = newSViv(PTR2IV(interval));
    OUTPUT:
	RETVAL


void
ngxe_interval_clear(p)
	void *p
    CODE:
	ngxe_interval_t   *interval;
	ngx_connection_t  *c;

	interval = (ngxe_interval_t *) p;
	c = interval->connection;

	ngxe_callback_dec(interval->callback);

	ngx_event_del_timer(c->read);

	ngx_destroy_pool(c->pool);
	ngx_free_connection(c);


SV *
ngxe_timeout_set(msec, sub, ...)
	int msec
	SV *sub
    CODE:
	ngx_connection_t  *c;
	ngxe_interval_t   *interval;
	ngxe_callback_t   *cb;
	int               i;

	c = ngx_get_connection((ngx_socket_t) 0, ngx_cycle->log);
	if (c == NULL) {
		XSRETURN_UNDEF;
	}
	
	c->read->handler = ngxe_timeout_callback;
	c->read->active = 1;
	c->log = ngx_cycle->log;
	c->read->log = ngx_cycle->log;
	c->pool = ngx_create_pool(128, c->log);
	
	interval = ngx_pcalloc(c->pool, sizeof(ngxe_interval_t));
	if (interval == NULL) {
		XSRETURN_UNDEF;
	}
	
	c->data = (void *) interval;

	interval->connection = c;
	interval->msec = msec;

	cb = ngx_pcalloc(c->pool, sizeof(ngxe_callback_t));
	if (cb == NULL) {
		XSRETURN_UNDEF;
	}
	
	interval->callback = cb;

	/* creating perl callback */

	cb->handler = sv_2mortal(newSVsv(sub));
	SvREFCNT_inc(cb->handler); 

	cb->args_n = (items - 2) + 1; 
	if (cb->args_n > 0) {
	    cb->args = ngx_pcalloc(c->pool, cb->args_n * sizeof(SV *));
	}

	cb->args[0] = sv_2mortal(newSViv(PTR2IV(interval)));
	SvREFCNT_inc(cb->args[0]);

	for (i = 1; i < cb->args_n; i++) {
	    cb->args[i] = sv_2mortal(newSVsv(ST((i+2)-1)));
	    SvREFCNT_inc(cb->args[i]);
	}

	/* */

	ngx_event_add_timer(c->read, msec);

	RETVAL = newSViv(PTR2IV(interval));
    OUTPUT:
	RETVAL



void
ngxe_timeout_clear(p)
	void *p
    CODE:
	ngxe_interval_t   *interval;
	ngx_connection_t  *c;

	interval = (ngxe_interval_t *) p;
	c = interval->connection;

	ngxe_callback_dec(interval->callback);
	ngx_event_del_timer(c->read);
	ngx_destroy_pool(c->pool);
	ngx_free_connection(c);





int
ngxe_reader(connection, start, timeout, sub, ...) 
	void  *connection
	int    start
	int    timeout
	SV    *sub
    CODE:
	ngx_connection_t    *c;
	ngxe_callback_t     *cb;
	ngx_pool_cleanup_t  *cbcln;
	ngxe_session_t      *s;
	int                  i, args_offset, args_extra;

	c = (ngx_connection_t *) connection;
	if (c == NULL || c->pool == NULL) {
		warn("Argument 0 (connection) is not a valid connection "
		     "pointer");
		XSRETURN_UNDEF;
	}

	s = (ngxe_session_t *) c->data;
	if (s == NULL) {
		warn("Connection doesn't have a session pointer");
		XSRETURN_UNDEF;
	}

	cb = ngx_pcalloc(c->pool, sizeof(ngxe_callback_t));
	if (cb == NULL) {
		warn("Failed to allocate memory for callback");
		XSRETURN_UNDEF;
	}

	cbcln = ngx_pool_cleanup_add(c->pool, 0);
	if (cbcln == NULL) {
		warn("Failed to allocate memory for callback's cleanup");
		XSRETURN_UNDEF;
	}

	cbcln->data = (void *) cb;
	cbcln->handler = ngxe_callback_cleanup;



	/* creating perl callback */

	args_offset = 4;
	args_extra  = 4;

	cb->handler = sv_2mortal(newSVsv(sub));
	SvREFCNT_inc(cb->handler); 

	cb->args_n = (items - args_offset) + args_extra; 
	if (cb->args_n > 0) {
		cb->args = ngx_pcalloc(c->pool, cb->args_n * sizeof(SV *));
	}

	/* $connection */
	cb->args[0] = sv_2mortal(newSViv(PTR2IV(c)));
	SvREFCNT_inc(cb->args[0]);
	SvIOK_only(cb->args[0]);

	/* $error */
	cb->args[1] = sv_2mortal(newSViv(0));
	SvREFCNT_inc(cb->args[1]);
	SvIOK_only(cb->args[1]);

	/* $reader_buffer */
	if (s->reader_buffer == NULL) {
		cb->args[2] = sv_2mortal(newSV(16384));
		SvREFCNT_inc(cb->args[2]);
		SvPOK_only(cb->args[2]);
		SvCUR_set(cb->args[2], 0);

		s->reader_buffer = cb->args[2]; 
	} else {
		cb->args[2] = s->reader_buffer; 
		SvREFCNT_inc(cb->args[2]);
	}

	/* $writer_buffer */
	if (s->writer_buffer == NULL) {
		/* cb->args[3] = sv_2mortal(newSV(32768-16)); */
		/* sv_setsv(cb->args[3], buffer); */
		cb->args[3] = sv_2mortal(newSV(1)); 
		SvREFCNT_inc(cb->args[3]);
		SvPOK_only(cb->args[3]);

		s->writer_buffer = cb->args[3];
	} else {
		cb->args[3] = s->writer_buffer; 
		SvREFCNT_inc(cb->args[3]);
	}

	/* ... */
	for (i = args_extra; i < cb->args_n; i++) {
		cb->args[i] = sv_2mortal(newSVsv(ST(i + args_offset - 
							args_extra)));
		SvREFCNT_inc(cb->args[i]);
	}

	/* */

	s->reader_callback = cb;
	s->reader_timeout = timeout;

	c->read->handler = ngxe_reader_handler;

	if (start) {
		ngxe_reader_start(c);
	}

	RETVAL = 1;

    OUTPUT:
	RETVAL



void
ngxe_reader_start(connection) 
	void  *connection
    CODE:
	ngxe_reader_start((ngx_connection_t *) connection);


void
ngxe_reader_stop(connection) 
	void  *connection
    CODE:
	ngxe_reader_stop((ngx_connection_t *) connection);



int
ngxe_writer(connection, start, timeout, buffer, sub, ...) 
	void  *connection
	int    start
	int    timeout
	SV    *buffer
	SV    *sub
    CODE:
	ngx_connection_t    *c;
	ngxe_callback_t     *cb;
	ngx_pool_cleanup_t  *cbcln;
	ngxe_session_t      *s;
	int                  i, args_offset, args_extra;

	c = (ngx_connection_t *) connection;
	if (c == NULL || c->pool == NULL) {
		warn("Argument 0 (connection) is not a valid connection "
		     "pointer");
		XSRETURN_UNDEF;
	}

	s = (ngxe_session_t *) c->data;
	if (s == NULL) {
		warn("Connection doesn't have a session pointer");
		XSRETURN_UNDEF;
	}

	cb = ngx_pcalloc(c->pool, sizeof(ngxe_callback_t));
	if (cb == NULL) {
		warn("Failed to allocate memory for callback");
		XSRETURN_UNDEF;
	}

	cbcln = ngx_pool_cleanup_add(c->pool, 0);
	if (cbcln == NULL) {
		warn("Failed to allocate memory for callback's cleanup");
		XSRETURN_UNDEF;
	}

	cbcln->data = (void *) cb;
	cbcln->handler = ngxe_callback_cleanup;


	/* creating perl callback */

	args_offset = 5;
	args_extra  = 4;

	cb->handler = sv_2mortal(newSVsv(sub));
	SvREFCNT_inc(cb->handler); 

	cb->args_n = (items - args_offset) + args_extra; 
	if (cb->args_n > 0) {
		cb->args = ngx_pcalloc(c->pool, cb->args_n * sizeof(SV *));
	}

	/* $connection */
	cb->args[0] = sv_2mortal(newSViv(PTR2IV(c)));
	SvREFCNT_inc(cb->args[0]);
	SvIOK_only(cb->args[0]);

	/* $error */
	cb->args[1] = sv_2mortal(newSViv(0));
	SvREFCNT_inc(cb->args[1]);
	SvIOK_only(cb->args[1]);

	/* $reader_buffer */
	if (s->reader_buffer == NULL) {
		cb->args[2] = sv_2mortal(newSV(16384));
		SvREFCNT_inc(cb->args[2]);
		SvPOK_only(cb->args[2]);
		SvCUR_set(cb->args[2], 0);

		s->reader_buffer = cb->args[2]; 
	} else {
		cb->args[2] = s->reader_buffer;
		SvREFCNT_inc(cb->args[2]);
	}

	/* $writer_buffer */
	if (s->writer_buffer == NULL) {
		/* cb->args[3] = sv_2mortal(newSV(32768-16)); */
		/* sv_setsv(cb->args[3], buffer); */
		cb->args[3] = sv_2mortal(newSVsv(buffer)); 
		SvREFCNT_inc(cb->args[3]);
		SvPOK_only(cb->args[3]);

		s->writer_buffer = cb->args[3];
	} else {
		cb->args[3] = s->writer_buffer;
		SvREFCNT_inc(cb->args[3]);
		sv_setsv(cb->args[3], buffer);
		SvPOK_only(cb->args[3]);
	}
	

	/* ... */
	for (i = args_extra; i < cb->args_n; i++) {
		cb->args[i] = sv_2mortal(newSVsv(ST(i + args_offset - 
							args_extra)));
		SvREFCNT_inc(cb->args[i]);
	}

	/* */

	s->writer_callback = cb;
	s->writer_timeout = timeout;

	c->write->handler = ngxe_writer_handler;

	if (start) {
		ngxe_writer_start(c);
	}

	RETVAL = 1;

    OUTPUT:
	RETVAL




void
ngxe_writer_start(connection) 
	void  *connection
    CODE:
	ngxe_writer_start((ngx_connection_t *) connection);


void
ngxe_writer_stop(connection) 
	void  *connection
    CODE:
	ngxe_writer_stop((ngx_connection_t *) connection);





void
ngxe_close(connection) 
	void  *connection
    CODE:
	ngxe_close((ngx_connection_t *) connection);





SV *
ngxe_client(bind_address, address, port, timeout, sub, ...) 
	char              *address
	char              *bind_address
	int                port
	int                timeout
	SV                *sub
    CODE:
	in_addr_t               inaddr, bind_inaddr;
	size_t                  inaddr_len, bind_inaddr_len;
	ngx_pool_t             *pool;
	ngx_peer_connection_t  *peer;
	ngx_connection_t       *c;
	ngxe_session_t         *s;
	ngxe_callback_t        *cb;
	ngx_pool_cleanup_t     *cbcln;
	ngx_int_t               rc;
	int                     i, args_offset, args_extra;

	if (*bind_address == 0 || *bind_address == '*') {
		bind_inaddr = INADDR_ANY;
	} else {
		bind_inaddr_len = ngx_strlen(bind_address);
		bind_inaddr = ngx_inet_addr((u_char *) bind_address, 
							bind_inaddr_len);
		if (bind_inaddr == INADDR_NONE) {
			warn("Argument 0 (bind_address) is not an IP address");
			XSRETURN_UNDEF;
		}
	}

	inaddr_len = ngx_strlen(address);
	inaddr = ngx_inet_addr((u_char *) address, inaddr_len);
	if (inaddr == INADDR_NONE) {
		warn("Argument 1 (address) is not an IP address");
		XSRETURN_UNDEF;
	}

	pool = ngx_create_pool(512, ngx_cycle->log);
	if (pool == NULL) {
		warn("Failed to create new nginx memory pool");
		XSRETURN_UNDEF;
	}

	peer = ngxe_create_peer(pool, bind_inaddr, inaddr, (in_port_t) port);
	if (peer == NULL) {
		warn("Failed to create new nginx peer");
		XSRETURN_UNDEF;
	}

	cb = ngx_pcalloc(pool, sizeof(ngxe_callback_t));
	if (cb == NULL) {
		warn("Failed to allocate memory for callback");
		XSRETURN_UNDEF;
	}

	cbcln = ngx_pool_cleanup_add(pool, 0);
	if (cbcln == NULL) {
		warn("Failed to allocate memory for callback's cleanup");
		XSRETURN_UNDEF;
	}

	cbcln->data = (void *) cb;
	cbcln->handler = ngxe_callback_cleanup;


	/* creating perl callback */

	args_offset = 5;
	args_extra  = 2;

	cb->handler = sv_2mortal(newSVsv(sub));
	SvREFCNT_inc(cb->handler); 

	cb->args_n = (items - args_offset) + args_extra; 
	if (cb->args_n > 0) {
		cb->args = ngx_pcalloc(pool, cb->args_n * sizeof(SV *));
	}

	/* $connection */
	cb->args[0] = sv_2mortal(newSViv(PTR2IV(0)));
	SvREFCNT_inc(cb->args[0]);
	SvIOK_only(cb->args[0]);

	/* $error */
	cb->args[1] = sv_2mortal(newSViv(0));
	SvREFCNT_inc(cb->args[1]);
	SvIOK_only(cb->args[1]);

	/* ... */
	for (i = args_extra; i < cb->args_n; i++) {
		cb->args[i] = sv_2mortal(newSVsv(ST(i + args_offset - 
							args_extra)));
		SvREFCNT_inc(cb->args[i]);
	}

	/* */


	rc = ngx_event_connect_peer(peer);
	if (rc == NGX_ERROR || rc == NGX_BUSY || rc == NGX_DECLINED) {
		sv_setiv(cb->args[1], 1); /* $error = 1 */
		ngxe_callback(cb, 1);

		if (peer->connection) {
			ngx_close_connection(peer->connection);
		}

		ngx_destroy_pool(pool);
		XSRETURN_UNDEF;
	}

	c = peer->connection;
	if (c == NULL) {
		sv_setiv(cb->args[1], 1); /* $error = 1 */
		ngxe_callback(cb, 1);

		ngx_destroy_pool(pool);
		XSRETURN_UNDEF;
	}

	c->pool = pool;
	c->log = peer->log;

	sv_setiv(cb->args[0], PTR2IV(c)); /* $connection */
	RETVAL = newSViv(PTR2IV(c));

        s = ngx_pcalloc(c->pool, sizeof(ngxe_session_t));
	if (s == NULL) {
		sv_setiv(cb->args[1], 1); /* $error = 1 */
		ngxe_callback(cb, 1);

		ngxe_close(c);
		XSRETURN_UNDEF;
	}

	c->data = (void *) s;

	s->writer_callback = cb;
	s->writer_timeout = timeout;

	c->write->handler = ngxe_client_init_handler;

	if (rc == NGX_OK) {
		c->write->handler(c->write);
	} else {
		ngx_event_add_timer(c->write, timeout);
	}

    OUTPUT:
	RETVAL






SV *
ngxe_server(address, port, sub, ...) 
	char              *address
	int                port
	SV                *sub
    CODE:
	in_addr_t            inaddr;
	size_t               nlen;
	ngx_connection_t    *c;
	ngxe_callback_t     *cb;
	ngx_pool_cleanup_t  *cbcln;
	int                  i, args_offset, args_extra;

	if (*address == 0 || *address == '*') {
		inaddr = INADDR_ANY;
	} else {
		nlen = ngx_strlen(address);
		inaddr = ngx_inet_addr((u_char *) address, nlen);
		if (inaddr == INADDR_NONE) {
			warn("Argument 0 (address) is not an IP address");
			XSRETURN_UNDEF;
		}
	}

	c = ngxe_server_create((ngx_cycle_t *) ngx_cycle, inaddr, 
							(in_port_t )port);


	cb = ngx_pcalloc(c->pool, sizeof(ngxe_callback_t));
	if (cb == NULL) {
		warn("Failed to allocate memory for callback");
		XSRETURN_UNDEF;
	}

	cbcln = ngx_pool_cleanup_add(c->pool, 0);
	if (cbcln == NULL) {
		warn("Failed to allocate memory for callback's cleanup");
		XSRETURN_UNDEF;
	}

	cbcln->data = (void *) cb;
	cbcln->handler = ngxe_callback_cleanup;


	/* creating perl callback */

	args_offset = 3;
	args_extra  = 2;

	cb->handler = sv_2mortal(newSVsv(sub));
	SvREFCNT_inc(cb->handler); 

	cb->args_n = (items - args_offset) + args_extra; 
	if (cb->args_n > 0) {
		cb->args = ngx_pcalloc(c->pool, cb->args_n * sizeof(SV *));
	}

	/* $connection */
	cb->args[0] = sv_2mortal(newSViv(PTR2IV(c)));
	SvREFCNT_inc(cb->args[0]);
	SvIOK_only(cb->args[0]);

	/* $addr */
	cb->args[1] = sv_2mortal(newSV(56));
	SvREFCNT_inc(cb->args[1]);
	SvPOK_only(cb->args[1]);

	/* ... */
	for (i = args_extra; i < cb->args_n; i++) {
		cb->args[i] = sv_2mortal(newSVsv(ST(i + args_offset - 
							args_extra)));
		SvREFCNT_inc(cb->args[i]);
	}

	/* */

	c->data = cb;

	RETVAL = newSViv(PTR2IV(c));
    OUTPUT:
	RETVAL





void 
ngxe_init(filename, usestderr, connections)
	char *filename
	int   usestderr
	int   connections
    CODE:
	ngx_ngxe_init(filename, usestderr, connections);


void
ngxe_loop()
    CODE:
	SAVETMPS;
	for (;;) {
		ngx_process_events_and_timers((ngx_cycle_t *) ngx_cycle);

		if (ngx_terminate || ngx_quit) {
		    break;
		}

		if (ngx_reopen) {
		    ngx_reopen = 0;
		    ngx_reopen_files((ngx_cycle_t *) ngx_cycle, (ngx_uid_t) -1);
        	}
	}
	FREETMPS;
