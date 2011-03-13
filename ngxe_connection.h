
#ifndef _NGXE_CONNECTION_H_INCLUDED_
#define _NGXE_CONNECTION_H_INCLUDED_

#include <ngxe_ngx.h>
#include <ngxe_xs.h>

typedef struct {
    /* reader */
    ngxe_callback_t  *reader_callback;
    SV               *reader_buffer;
    int               reader_timeout;
    int               reader_flags;

    /* writer */
    ngxe_callback_t  *writer_callback;
    SV               *writer_buffer;
    int               writer_timeout;
    int               writer_offset;
    int               writer_index;

    void             *data;
} ngxe_session_t;


typedef struct {
    int               keepalive;
    int               keepalive_timeout;
} ngxe_http_session_t;


void  ngxe_reader_start(ngx_connection_t *c);
void  ngxe_reader_stop(ngx_connection_t *c);
void  ngxe_writer_start(ngx_connection_t *c);
void  ngxe_writer_stop(ngx_connection_t *c);
void  ngxe_close(ngx_connection_t *c);

ngx_listening_t 	*ngxe_server_create(ngx_cycle_t *cycle, 
			    in_addr_t addr, in_port_t port);
ngx_peer_connection_t 	*ngxe_create_peer(ngx_pool_t *pool, 
			    in_addr_t bindaddr, in_addr_t addr, 
			    in_port_t port);

void  ngxe_dummy_handler(ngx_event_t *ev);
void  ngxe_reader_handler(ngx_event_t *ev);
void  ngxe_writer_handler(ngx_event_t *ev);
void  ngxe_client_init_handler(ngx_event_t *ev);

void  ngxe_connection_bufsize_init(ngx_int_t bufsize);

void  ngxe_http_server_init_connection(ngx_connection_t *c);
void  ngxe_http_server_reader(ngx_connection_t *c);
void  ngxe_http_server_writer(ngx_connection_t *c);

#endif /* _NGXE_CONNECTION_H_INCLUDED_ */


