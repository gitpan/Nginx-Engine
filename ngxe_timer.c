
#include <ngxe.h>

void 
ngxe_interval_callback(ngx_event_t *ev) 
{
	ngx_connection_t  *c;
	ngxe_interval_t   *interval;

	c = (ngx_connection_t *) ev->data;
	interval = (ngxe_interval_t *) c->data;

	ngx_event_add_timer(ev, interval->msec);

	ngxe_callback(interval->callback, 0);

	return;
}


void 
ngxe_timeout_callback(ngx_event_t *ev) 
{
	ngx_connection_t  *c;
	ngxe_interval_t   *interval;

	c = (ngx_connection_t *) ev->data;
	interval = (ngxe_interval_t *) c->data;

	ngxe_callback(interval->callback, 1);

	ngx_destroy_pool(c->pool);
	ngx_free_connection(c);

	return;
}



