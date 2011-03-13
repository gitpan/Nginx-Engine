
#ifndef _NGXE_NGX_H_INCLUDED_
#define _NGXE_NGX_H_INCLUDED_

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_event_connect.h>
#include <nginx.h>

ngx_int_t  ngx_ngxe_init(char *logfilename, int usestderr, int connections);
ngx_int_t  ngx_ngxe_init_signals();
ngx_int_t  ngx_ngxe_add_listening_connection(ngx_listening_t *ls);
void  ngx_ngxe_open_listening_socket(ngx_listening_t *ls);
ngx_listening_t  *ngx_ngxe_create_listening(ngx_pool_t *pool, 
	void *sockaddr, socklen_t socklen);

#endif /* _NGXE_NGX_H_INCLUDED_ */
