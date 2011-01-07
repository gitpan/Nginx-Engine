
#include <ngxe.h>

static int ngxe_initialized;

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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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
	args_extra  = 5;

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

	/* $min_len */
	cb->args[4] = sv_2mortal(newSViv(0));
	SvREFCNT_inc(cb->args[4]);
	SvIOK_only(cb->args[4]);

	/* ... */
	for (i = args_extra; i < cb->args_n; i++) {
		cb->args[i] = sv_2mortal(newSVsv(ST(i + args_offset - 
							args_extra)));
		SvREFCNT_inc(cb->args[i]);
	}

	/* */

	s->reader_flags = start;

	s->reader_callback = cb;
	s->reader_timeout = timeout;

	c->read->handler = ngxe_dummy_handler;

	if (start & NGXE_START) {
		ngxe_reader_start(c);
	}

	RETVAL = 1;

    OUTPUT:
	RETVAL



int
ngxe_reader_timeout(connection, ...) 
	void  *connection
    CODE:
	ngx_connection_t    *c;
	ngxe_session_t      *s;

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (items > 2) {
		warn("Too many arguments for ngxe_reader_timeout (ignored)");
	}

	RETVAL = s->reader_timeout;

	if (items >= 2) {
		s->reader_timeout = SvIV(ST(1));
	}
    OUTPUT:
	RETVAL


int
ngxe_writer_timeout(connection, ...) 
	void  *connection
    CODE:
	ngx_connection_t    *c;
	ngxe_session_t      *s;

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (items > 2) {
		warn("Too many arguments for ngxe_writer_timeout (ignored)");
	}

	RETVAL = s->writer_timeout;

	if (items >= 2) {
		s->writer_timeout = SvIV(ST(1));
	}
    OUTPUT:
	RETVAL



void
ngxe_writer_buffer_set(connection, data) 
	void  *connection
	SV    *data
    CODE:
	ngx_connection_t    *c;
	ngxe_session_t      *s;

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (items > 2) {
		croak("Too many arguments for ngxe_writer_append");
		XSRETURN_UNDEF;
	}

	if (s->writer_buffer != NULL) {
		if (SvCUR(data) == 0) {
			XSRETURN_UNDEF;
		}

		sv_setsv(s->writer_buffer, data);
		SvPOK_only(s->writer_buffer);

		ngxe_writer_start(c);
	} else {
		warn("s->writer_buffer is not initialized, ignoring");
		XSRETURN_UNDEF;
	}




void
ngxe_reader_start(connection, ...) 
	void  *connection
    CODE:
	ngx_connection_t    *c;
	ngxe_session_t      *s;

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (items > 2) {
		warn("Too many arguments for ngxe_reader_start (ignored)");
	}

	if (items >= 2) {
		/* updating reader_timeout */
		s->reader_timeout = SvIV(ST(1));
	}

	ngxe_reader_start(c);


void
ngxe_reader_stop(connection) 
	void  *connection
    CODE:
	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

	ngxe_reader_stop((ngx_connection_t *) connection);



void
ngxe_reader_stop_writer_start(connection) 
	void  *connection
    CODE:
	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

	ngxe_reader_stop((ngx_connection_t *) connection);
	ngxe_writer_start((ngx_connection_t *) connection);



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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	c->write->handler = ngxe_dummy_handler;

	if (start & NGXE_START) {
		ngxe_writer_start(c);
	}

	RETVAL = 1;

    OUTPUT:
	RETVAL




void
ngxe_writer_start(connection, ...) 
	void  *connection
    CODE:
	ngx_connection_t    *c;
	ngxe_session_t      *s;

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (items > 2) {
		warn("Too many arguments for ngxe_writer_start (ignored)");
	}

	if (items >= 2) {
		/* updating writer_timeout */
		s->writer_timeout = SvIV(ST(1));
	}
	ngxe_writer_start((ngx_connection_t *) connection);


void
ngxe_writer_stop(connection) 
	void  *connection
    CODE:
	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

	ngxe_writer_stop((ngx_connection_t *) connection);



void
ngxe_writer_stop_reader_start(connection) 
	void  *connection
    CODE:
	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

	ngxe_writer_stop((ngx_connection_t *) connection);
	ngxe_reader_start((ngx_connection_t *) connection);






void
ngxe_close(connection) 
	void  *connection
    CODE:
	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	pool = ngx_create_pool(1024, ngx_cycle->log);
	if (pool == NULL) {
		warn("Failed to create new nginx memory pool");
		XSRETURN_UNDEF;
	}

	peer = ngxe_create_peer(pool, bind_inaddr, inaddr, (in_port_t) port);
	if (peer == NULL) {
		warn("Failed to create new nginx peer");
		ngx_destroy_pool(pool);
		XSRETURN_UNDEF;
	}

	cb = ngx_pcalloc(pool, sizeof(ngxe_callback_t));
	if (cb == NULL) {
		warn("Failed to allocate memory for callback");
		ngx_destroy_pool(pool);
		XSRETURN_UNDEF;
	}

	cbcln = ngx_pool_cleanup_add(pool, 0);
	if (cbcln == NULL) {
		warn("Failed to allocate memory for callback's cleanup");
		ngx_destroy_pool(pool);
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

	/* saving address as a name, required for logging  */
	peer->name->len = inaddr_len;
	peer->name->data = ngx_pnalloc(pool, peer->name->len);
	if (peer->name->data == NULL) {
		warn("Failed to allocate memory for peer->name->data");
		ngx_destroy_pool(pool);
		XSRETURN_UNDEF;
	}
	ngx_memcpy(peer->name->data, address, peer->name->len); 

	rc = ngx_event_connect_peer(peer);
	if (rc == NGX_ERROR || rc == NGX_BUSY || rc == NGX_DECLINED) {

		sv_setiv(cb->args[1], -1); 
		sv_setpv(cb->args[1], "Connection failed");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		if (peer->connection) {
			ngx_close_connection(peer->connection);
		}

		ngx_destroy_pool(pool);
		XSRETURN_UNDEF;
	}

	c = peer->connection;
	if (c == NULL) {

		sv_setiv(cb->args[1], -1); 
		sv_setpv(cb->args[1], "Connection error");
		SvIOK_on(cb->args[1]);

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

		sv_setiv(cb->args[1], -1); 
		sv_setpv(cb->args[1], "Cannot allocate memory for session");
		SvIOK_on(cb->args[1]);

		ngxe_callback(cb, 1);

		ngxe_close(c);
		XSRETURN_UNDEF;
	}

	c->data = (void *) s;

	s->writer_callback = cb;
	s->writer_timeout = timeout;

	c->write->handler = ngxe_client_init_handler;
	c->read->handler = ngxe_client_init_handler;

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

	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

	if (c == NULL) {
	    warn("ngxe_server_create() failed");
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
ngxe_init(filename, ...)
	char *filename
    CODE:
	int connections;

	if (ngxe_initialized == 1) {
		croak("Already initialized");
		XSRETURN_UNDEF;
	}

	connections = 512;

	if (items == 3) { /* compatible with old ngxe_init() */
		connections = SvIV(ST(2));
	} else if (items >= 2) {
		connections = SvIV(ST(1));
	}

	if (connections < 16) {
		warn("Number of connections is too low, using 16 instead");
		connections = 16;
	}

	ngx_ngxe_init(filename, 0, connections);

	ngxe_initialized = 1;


void
ngxe_loop()
    CODE:
	if (ngxe_initialized != 1) {
		croak("You need to call ngxe_init() first");
		XSRETURN_UNDEF;
	}

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

