
#include <ngxe.h>

struct rlimit  rlmt;

static ngx_log_t        ngx_log;
static ngx_open_file_t  ngx_log_file;


static ngx_int_t
ngx_events_modules_init(ngx_cycle_t *cycle)
{
    char                 *rv;
    void              ***ctx;
    ngx_uint_t            i;
    ngx_event_module_t   *m;
    ngx_uint_t            ngx_event_max_module;

    /* count the number of the event modules and set up their indices */

    ngx_event_max_module = 0;
    for (i = 0; ngx_modules[i]; i++) {
        if (ngx_modules[i]->type != NGX_EVENT_MODULE) {
            continue;
        }

        ngx_modules[i]->ctx_index = ngx_event_max_module++;
    }

    ctx = ngx_pcalloc(cycle->pool, sizeof(void *));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    *ctx = ngx_pcalloc(cycle->pool, ngx_event_max_module * sizeof(void *));
    if (*ctx == NULL) {
        return NGX_ERROR;
    }


    cycle->conf_ctx[ngx_events_module.index] = ctx;


    for (i = 0; ngx_modules[i]; i++) {
        if (ngx_modules[i]->type != NGX_EVENT_MODULE) {
            continue;
        }

        m = ngx_modules[i]->ctx;

        if (m->create_conf) {
            (*ctx)[ngx_modules[i]->ctx_index] = m->create_conf(cycle);
            if ((*ctx)[ngx_modules[i]->ctx_index] == NULL) {
                return NGX_ERROR;
            }
        }
    }



    for (i = 0; ngx_modules[i]; i++) {
        if (ngx_modules[i]->type != NGX_EVENT_MODULE) {
            continue;
        }

        m = ngx_modules[i]->ctx;

        if (m->init_conf) {
            rv = m->init_conf(cycle, (*ctx)[ngx_modules[i]->ctx_index]);
            if (rv != NGX_CONF_OK) {
                return NGX_ERROR;
            }
        }
    }

    return NGX_OK;
}


static ngx_log_t *
ngx_ngxe_log_init(u_char *logfilename)
{
    u_char  *name;
    size_t   nlen;

    ngx_log.file = &ngx_log_file;
    ngx_log.log_level = NGX_LOG_NOTICE; 
    /* ngx_log.log_level = NGX_LOG_DEBUG_ALL; */

    /*
     * we use ngx_strlen() here since BCC warns about
     * condition is always false and unreachable code
     */

    nlen = ngx_strlen(logfilename);

    if (nlen == 0) {
        ngx_log_file.fd = ngx_stderr;
        return &ngx_log;
    }

    name = malloc(nlen + 2);
    if (name == NULL) {
	return NULL;
    }

    ngx_cpystrn(name, logfilename, nlen + 1);

    ngx_log_file.fd = ngx_open_file(name, NGX_FILE_APPEND,
                                    NGX_FILE_CREATE_OR_OPEN,
                                    NGX_FILE_DEFAULT_ACCESS);

    if (ngx_log_file.fd == NGX_INVALID_FILE) {
        ngx_log_stderr(ngx_errno,
                       "[alert]: could not open error log file: "
                       ngx_open_file_n " \"%s\" failed", name);
#if (NGX_WIN32)
        ngx_event_log(ngx_errno,
                       "could not open error log file: "
                       ngx_open_file_n " \"%s\" failed", name);
#endif

        ngx_log_file.fd = ngx_stderr;
    }

    return &ngx_log;
}


ngx_listening_t *
ngx_ngxe_create_listening(ngx_pool_t *pool, void *sockaddr, socklen_t socklen)
{
    size_t            len;
    ngx_listening_t  *ls;
    struct sockaddr  *sa;
    u_char            text[NGX_SOCKADDR_STRLEN];

    ls = ngx_pcalloc(pool, sizeof(ngx_listening_t));
    if (ls == NULL) {
        return NULL;
    }

    ngx_memzero(ls, sizeof(ngx_listening_t));

    sa = ngx_palloc(pool, socklen);
    if (sa == NULL) {
        return NULL;
    }

    ngx_memcpy(sa, sockaddr, socklen);

    ls->sockaddr = sa;
    ls->socklen = socklen;

    len = ngx_sock_ntop(sa, text, NGX_SOCKADDR_STRLEN, 1);
    ls->addr_text.len = len;

    switch (ls->sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
    case AF_INET6:
         ls->addr_text_max_len = NGX_INET6_ADDRSTRLEN;
         break;
#endif
#if (NGX_HAVE_UNIX_DOMAIN)
    case AF_UNIX:
         ls->addr_text_max_len = NGX_UNIX_ADDRSTRLEN;
         len++;
         break;
#endif
    case AF_INET:
         ls->addr_text_max_len = NGX_INET_ADDRSTRLEN;
         break;
    default:
         ls->addr_text_max_len = NGX_SOCKADDR_STRLEN;
         break;
    }

    ls->addr_text.data = ngx_pnalloc(pool, len);
    if (ls->addr_text.data == NULL) {
        return NULL;
    }

    ngx_memcpy(ls->addr_text.data, text, len);

    ls->fd = (ngx_socket_t) -1;
    ls->type = SOCK_STREAM;

    ls->backlog = NGX_LISTEN_BACKLOG;
    ls->rcvbuf = -1;
    ls->sndbuf = -1;

#if (NGX_HAVE_SETFIB)
    ls->setfib = -1;
#endif

    return ls;
}

void
ngx_ngxe_open_listening_socket(ngx_listening_t *ls)
{
    int               reuseaddr;
    ngx_err_t         err;
    ngx_socket_t      s;
    ngx_log_t        *log;

    reuseaddr = 1;
    
    log = ls->logp;

    if (ls->ignore) {
	return;
    }

    if (ls->fd != -1) {
	return;
    }

    if (ls->inherited) {

	/* TODO: close on exit */
	/* TODO: nonblocking */
	/* TODO: deferred accept */

	return;
    }

    s = ngx_socket(ls->sockaddr->sa_family, ls->type, 0);

    if (s == -1) {
	ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
		      ngx_socket_n " %V failed", &ls->addr_text);
	return;
    }

    if (setsockopt(s, SOL_SOCKET, SO_REUSEADDR,
		   (const void *) &reuseaddr, sizeof(int))
	== -1)
    {
	ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
		      "setsockopt(SO_REUSEADDR) %V failed",
		      &ls->addr_text);

	if (ngx_close_socket(s) == -1) {
	    ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
			  ngx_close_socket_n " %V failed",
			  &ls->addr_text);
	}

	return;
    }

#if (NGX_HAVE_INET6 && defined IPV6_V6ONLY)

    if (ls->sockaddr->sa_family == AF_INET6 && ls->ipv6only) {
	int  ipv6only;

	ipv6only = (ls->ipv6only == 1);

	if (setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY,
		       (const void *) &ipv6only, sizeof(int))
	    == -1)
	{
	    ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
			  "setsockopt(IPV6_V6ONLY) %V failed, ignored",
			  &ls->addr_text);
	}
    }
#endif
    /* TODO: close on exit */

    if (!(ngx_event_flags & NGX_USE_AIO_EVENT)) {
	if (ngx_nonblocking(s) == -1) {
	    ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
			  ngx_nonblocking_n " %V failed",
			  &ls->addr_text);

	    if (ngx_close_socket(s) == -1) {
		ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
			      ngx_close_socket_n " %V failed",
			      &ls->addr_text);
	    }

	    return;
	}
    }

    ngx_log_debug2(NGX_LOG_DEBUG_CORE, log, 0,
		   "bind() %V #%d ", &ls->addr_text, s);

    if (bind(s, ls->sockaddr, ls->socklen) == -1) {
	err = ngx_socket_errno;

	if (err == NGX_EADDRINUSE && ngx_test_config) {
	    return;
	}

	ngx_log_error(NGX_LOG_EMERG, log, err,
		      "bind() to %V failed", &ls->addr_text);

	if (ngx_close_socket(s) == -1) {
	    ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
			  ngx_close_socket_n " %V failed",
			  &ls->addr_text);
	}

	if (err != NGX_EADDRINUSE) {
	    return;
	}

	return;
    }

#if (NGX_HAVE_UNIX_DOMAIN)

    if (ls->sockaddr->sa_family == AF_UNIX) {
	mode_t   mode;
	u_char  *name;

	name = ls->addr_text.data + sizeof("unix:") - 1;
	mode = (S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH);

	if (chmod((char *) name, mode) == -1) {
	    ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
			  "chmod() \"%s\" failed", name);
	}

	if (ngx_test_config) {
	    if (ngx_delete_file(name) == -1) {
		ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
			      ngx_delete_file_n " %s failed", name);
	    }
	}
    }
#endif

    if (listen(s, ls->backlog) == -1) {
	ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
		      "listen() to %V, backlog %d failed",
		      &ls->addr_text, ls->backlog);

	if (ngx_close_socket(s) == -1) {
	    ngx_log_error(NGX_LOG_EMERG, log, ngx_socket_errno,
			  ngx_close_socket_n " %V failed",
			  &ls->addr_text);
	}

	return;
    }

    ls->listen = 1;

    ls->fd = s;

}

ngx_int_t
ngx_ngxe_add_listening_connection(ngx_listening_t *ls)
{
    ngx_connection_t  *c, *old;
    ngx_event_t       *rev;

    c = ngx_get_connection(ls->fd, ls->logp);

    if (c == NULL) {
	return NGX_ERROR;
    }

    c->log = ls->logp;

    c->listening = ls;
    ls->connection = c;

    rev = c->read;

    rev->log = c->log;
    rev->accept = 1;

#if (NGX_HAVE_DEFERRED_ACCEPT)
    rev->deferred_accept = ls->deferred_accept;
#endif

    if (!(ngx_event_flags & NGX_USE_IOCP_EVENT)) {
	if (ls->previous) {

	    /*
	     * delete the old accept events that were bound to
	     * the old cycle read events array
	     */

	    old = ls->previous->connection;

	    if (ngx_del_event(old->read, NGX_READ_EVENT, NGX_CLOSE_EVENT)
		== NGX_ERROR)
	    {
		return NGX_ERROR;
	    }

	    old->fd = (ngx_socket_t) -1;
	}
    }

#if (NGX_WIN32)

    if (ngx_event_flags & NGX_USE_IOCP_EVENT) {
	ngx_iocp_conf_t  *iocpcf;

	rev->handler = ngx_event_acceptex;

	if (ngx_add_event(rev, 0, NGX_IOCP_ACCEPT) == NGX_ERROR) {
	    return NGX_ERROR;
	}

	ls->log.handler = ngx_acceptex_log_error;

	iocpcf = ngx_event_get_conf(cycle->conf_ctx, ngx_iocp_module);
	if (ngx_event_post_acceptex(ls, iocpcf->post_acceptex)
	    == NGX_ERROR)
	{
	    return NGX_ERROR;
	}

    } else {
	rev->handler = ngx_event_accept;

	if (ngx_add_event(rev, NGX_READ_EVENT, 0) == NGX_ERROR) {
	    return NGX_ERROR;
	}
    }

#else

    rev->handler = ngx_event_accept;

    if (ngx_event_flags & NGX_USE_RTSIG_EVENT) {
	if (ngx_add_conn(c) == NGX_ERROR) {
	    return NGX_ERROR;
	}

    } else {
	if (ngx_add_event(rev, NGX_READ_EVENT, 0) == NGX_ERROR) {
	    return NGX_ERROR;
	}
    }

#endif

    return NGX_OK;
}



static ngx_int_t
ngx_ngxe_os_init(ngx_log_t *log)
{
    ngx_uint_t  n;

#if (NGX_HAVE_OS_SPECIFIC_INIT)
    if (ngx_os_specific_init(log) != NGX_OK) {
	return NGX_ERROR;
    }
#endif

    /*
    *  ngx_init_setproctitle(log);
    */

    ngx_pagesize = getpagesize();
    ngx_cacheline_size = NGX_CPU_CACHE_LINE;

    for (n = ngx_pagesize; n >>= 1; ngx_pagesize_shift++) { /* void */ }

    if (ngx_ncpu == 0) {
	ngx_ncpu = 1;
    }

    ngx_cpuinfo();

    if (getrlimit(RLIMIT_NOFILE, &rlmt) == -1) {
	ngx_log_error(NGX_LOG_ALERT, log, errno,
	              "getrlimit(RLIMIT_NOFILE) failed)");
	return NGX_ERROR;
    }

    ngx_max_sockets = (ngx_int_t) rlmt.rlim_cur;

#if (NGX_HAVE_INHERITED_NONBLOCK)
    ngx_inherited_nonblocking = 1;
#else
    ngx_inherited_nonblocking = 0;
#endif

    srandom(ngx_time());

    return NGX_OK;
}


ngx_int_t
ngx_ngxe_init_signals() 
{

/*
#if !(NGX_WIN32)
    if (ngx_init_signals(ngx_cycle->log) != NGX_OK) {
        return 1;
    }
#endif
*/
    return 0;
}


ngx_int_t
ngx_ngxe_init(char *logfilename, int usestderr, int connections)
{
    ngx_log_t        *log;
    ngx_pool_t       *pool;
    ngx_cycle_t      *cycle;
    void             *rv;
    ngx_int_t         i;


    ngx_max_sockets = -1;

    ngx_time_init();


    log = ngx_ngxe_log_init((u_char *) logfilename);
    if (log == NULL) {
        return 1;
    }


    if (ngx_ngxe_os_init(log) != NGX_OK) {
        return 1;
    }

    pool = ngx_create_pool(NGX_CYCLE_POOL_SIZE, log);
    if (pool == NULL) {
        return 1;
    }
    
    pool->log = log;


    cycle = ngx_pcalloc(pool, sizeof(ngx_cycle_t));
    if (cycle == NULL) {
        ngx_destroy_pool(pool);
        return 1;
    }

    cycle->pool = pool;
    cycle->log = log;
    cycle->new_log.log_level = NGX_LOG_ERR;
    cycle->old_cycle = cycle; /*  */
    ngx_cycle = cycle;

    /* ngx_crc32_table_init uses ngx_cycle->log and cannot 
     * be initialized earlier 
     */
    if (ngx_crc32_table_init() != NGX_OK) {
        return 1;
    }

#if !(NGX_WIN32)
    if (ngx_init_signals(cycle->log) != NGX_OK) {
        ngx_destroy_pool(pool);
        return 1;
    }
#endif

    ngx_os_status(log);


    ngx_use_stderr = 0;
    if (usestderr) 
        ngx_use_stderr = 1;



    ngx_max_module = 0;
    for (i = 0; ngx_modules[i]; i++) {
        ngx_modules[i]->index = ngx_max_module++;
    }



    cycle->conf_ctx = ngx_pcalloc(cycle->pool, ngx_max_module * sizeof(void *));
    if (cycle->conf_ctx == NULL) {
        ngx_destroy_pool(pool);
        return 1;
    }


    rv = ((ngx_core_module_t *) ngx_core_module.ctx)->create_conf(cycle);
    if (rv == NULL) {
        ngx_destroy_pool(pool);
	return 1;
    }

    cycle->conf_ctx[ngx_core_module.index] = rv;


    if (((ngx_core_module_t *) ngx_core_module.ctx)->init_conf(cycle,
		cycle->conf_ctx[ngx_core_module.index]) == NGX_CONF_ERROR) 
    {
        ngx_destroy_pool(pool);
	return 1;
    }



    rv = ((ngx_event_module_t *) ngx_event_core_module.ctx)->create_conf(cycle);
    if (rv == NULL) {
        ngx_destroy_pool(pool);
	return 1;
    }

    cycle->conf_ctx[ngx_event_core_module.index] = rv;


    if (((ngx_event_module_t *) ngx_event_core_module.ctx)->init_conf(cycle,
		cycle->conf_ctx[ngx_event_core_module.index]) == NGX_CONF_ERROR) 
    {
        ngx_destroy_pool(pool);
	return 1;
    }


    if (ngx_events_modules_init(cycle) == NGX_ERROR) {
        ngx_destroy_pool(pool);
	return 1;
    }



    if (ngx_event_core_module.init_module(cycle) == NGX_ERROR) {
        ngx_destroy_pool(pool);
	return 1;
    }




    cycle->connection_n = connections;

    if (ngx_event_core_module.init_process(cycle) == NGX_ERROR) {
        ngx_destroy_pool(pool);
	return 1;
    }



    return 0;
}





