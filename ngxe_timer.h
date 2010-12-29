
#ifndef _NGXE_TIMER_H_INCLUDED_
#define _NGXE_TIMER_H_INCLUDED_

#include <ngxe_ngx.h>
#include <ngxe_xs.h>


struct ngxe_interval_s {
	int		   msec;
	ngxe_callback_t   *callback;
	ngx_connection_t  *connection;
};

typedef struct ngxe_interval_s  ngxe_interval_t;

void  ngxe_interval_callback(ngx_event_t *ev);
void  ngxe_timeout_callback(ngx_event_t *ev);


#endif /* _NGXE_TIMER_H_INCLUDED_ */

