
#ifndef _NGXE_DEBUG_H_INCLUDED_
#define _NGXE_DEBUG_H_INCLUDED_

#include <ngxe_ngx.h>

#ifdef DEBUG
#ifndef NGXE_DEBUG
#define NGXE_DEBUG
#endif  /* NGXE_DEBUG */
#endif /* DEBUG */

#ifdef NGXE_DEBUG
#define ngxe_debug(...) \
    ngx_log_error_core(NGX_LOG_DEBUG, ngx_cycle->log, 0, __VA_ARGS__);
#else
#define ngxe_debug(...) 
#endif

#ifdef NGXE_DEBUG_TIMER
#define ngxe_debug_timer(...) \
    ngx_log_error_core(NGX_LOG_DEBUG, ngx_cycle->log, 0, __VA_ARGS__);
#else
#define ngxe_debug_timer(...) 
#endif


#endif /* _NGXE_DEBUG_H_INCLUDED_ */


