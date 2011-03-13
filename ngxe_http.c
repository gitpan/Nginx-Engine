
#include <ngxe.h>

/* XXX based on HTTP-Parser-XS-0.13 */

/* $Id: 9cd312b6fcefb127a2edf2b2e60702d3f5b9abf7 $ */

#if __GNUC__ >= 3
# define likely(x)	__builtin_expect(!!(x), 1)
# define unlikely(x)	__builtin_expect(!!(x), 0)
#else
# define likely(x) (x)
# define unlikely(x) (x)
#endif

#define CHECK_EOF()	\
  if (buf == buf_end) {	\
    *ret = -2;		\
    return NULL;	\
  }

#define EXPECT_CHAR(ch) \
  CHECK_EOF();		\
  if (*buf++ != ch) {	\
    *ret = -1;		\
    return NULL;	\
  }

#define ADVANCE_TOKEN(tok, toklen) do {		       \
    const char* tok_start = buf; 		       \
    for (; ; ++buf) {				       \
      CHECK_EOF();				       \
      if (*buf == ' ') {			       \
	break;					       \
      } else if (*buf == '\015' || *buf == '\012') {   \
	*ret = -1;				       \
	return NULL;				       \
      }						       \
    }						       \
    tok = tok_start;				       \
    toklen = buf - tok_start;			       \
  } while (0)

static const char* get_token_to_eol(const char* buf, const char* buf_end,
				    const char** token, size_t* token_len,
				    int* ret)
{
  const char* token_start = buf;
  
  while (1) {
    if (likely(buf_end - buf >= 16)) {
      unsigned i;
      for (i = 0; i < 16; i++, ++buf) {
	if (unlikely((unsigned char)*buf <= '\015')
	    && (*buf == '\015' || *buf == '\012')) {
	  goto EOL_FOUND;
	}
      }
    } else {
      for (; ; ++buf) {
	CHECK_EOF();
	if (unlikely((unsigned char)*buf <= '\015')
	    && (*buf == '\015' || *buf == '\012')) {
	  goto EOL_FOUND;
	}
      }
    }
  }
 EOL_FOUND:
  if (*buf == '\015') {
    ++buf;
    EXPECT_CHAR('\012');
    *token_len = buf - 2 - token_start;
  } else { /* should be: *buf == '\012' */
    *token_len = buf - token_start;
    ++buf;
  }
  *token = token_start;
  
  return buf;
}
  
static const char* is_complete(const char* buf, const char* buf_end,
			       size_t last_len, int* ret)
{
  int ret_cnt = 0;
  buf = last_len < 3 ? buf : buf + last_len - 3;
  
  while (1) {
    CHECK_EOF();
    if (*buf == '\015') {
      ++buf;
      CHECK_EOF();
      EXPECT_CHAR('\012');
      ++ret_cnt;
    } else if (*buf == '\012') {
      ++buf;
      ++ret_cnt;
    } else {
      ++buf;
      ret_cnt = 0;
    }
    if (ret_cnt == 2) {
      return buf;
    }
  }
  
  *ret = -2;
  return NULL;
}

/* *_buf is always within [buf, buf_end) upon success */
static const char* parse_int(const char* buf, const char* buf_end, int* value,
			     int* ret)
{
  int v;
  CHECK_EOF();
  if (! ('0' <= *buf && *buf <= '9')) {
    *ret = -1;
    return NULL;
  }
  v = 0;
  for (; ; ++buf) {
    CHECK_EOF();
    if ('0' <= *buf && *buf <= '9') {
      v = v * 10 + *buf - '0';
    } else {
      break;
    }
  }
  
  *value = v;
  return buf;
}

/* returned pointer is always within [buf, buf_end), or null */
static const char* parse_http_version(const char* buf, const char* buf_end,
				      int* minor_version, int* ret)
{
  EXPECT_CHAR('H'); EXPECT_CHAR('T'); EXPECT_CHAR('T'); EXPECT_CHAR('P');
  EXPECT_CHAR('/'); EXPECT_CHAR('1'); EXPECT_CHAR('.');
  return parse_int(buf, buf_end, minor_version, ret);
}

static const char* parse_headers(const char* buf, const char* buf_end,
				 struct phr_header* headers,
				 size_t* num_headers, size_t max_headers,
				 int* ret)
{
  for (; ; ++*num_headers) {
    CHECK_EOF();
    if (*buf == '\015') {
      ++buf;
      EXPECT_CHAR('\012');
      break;
    } else if (*buf == '\012') {
      ++buf;
      break;
    }
    if (*num_headers == max_headers) {
      *ret = -1;
      return NULL;
    }
    if (*num_headers == 0 || ! (*buf == ' ' || *buf == '\t')) {
      /* parsing name, but do not discard SP before colon, see
       * http://www.mozilla.org/security/announce/2006/mfsa2006-33.html */
      headers[*num_headers].name = buf;
      for (; ; ++buf) {
	CHECK_EOF();
	if (*buf == ':') {
	  break;
	} else if (*buf < ' ') {
	  *ret = -1;
	  return NULL;
	}
      }
      headers[*num_headers].name_len = buf - headers[*num_headers].name;
      ++buf;
      for (; ; ++buf) {
	CHECK_EOF();
	if (! (*buf == ' ' || *buf == '\t')) {
	  break;
	}
      }
    } else {
      headers[*num_headers].name = NULL;
      headers[*num_headers].name_len = 0;
    }
    if ((buf = get_token_to_eol(buf, buf_end, &headers[*num_headers].value,
				&headers[*num_headers].value_len, ret))
	== NULL) {
      return NULL;
    }
  }
  return buf;
}

const char* parse_request(const char* buf, const char* buf_end,
			  const char** method, size_t* method_len,
			  const char** path, size_t* path_len,
			  int* minor_version, struct phr_header* headers,
			  size_t* num_headers, size_t max_headers, int* ret)
{
  /* skip first empty line (some clients add CRLF after POST content) */
  CHECK_EOF();
  if (*buf == '\015') {
    ++buf;
    EXPECT_CHAR('\012');
  } else if (*buf == '\012') {
    ++buf;
  }
  
  /* parse request line */
  ADVANCE_TOKEN(*method, *method_len);
  ++buf;
  ADVANCE_TOKEN(*path, *path_len);
  ++buf;
  if ((buf = parse_http_version(buf, buf_end, minor_version, ret)) == NULL) {
    return NULL;
  }
  if (*buf == '\015') {
    ++buf;
    EXPECT_CHAR('\012');
  } else if (*buf == '\012') {
    ++buf;
  } else {
    *ret = -1;
    return NULL;
  }
  
  return parse_headers(buf, buf_end, headers, num_headers, max_headers, ret);
}

int phr_parse_request(const char* buf_start, size_t len, const char** method,
		      size_t* method_len, const char** path, size_t* path_len,
		      int* minor_version, struct phr_header* headers,
		      size_t* num_headers, size_t last_len)
{
  const char * buf = buf_start, * buf_end = buf_start + len;
  size_t max_headers = *num_headers;
  int r;
  
  *method = NULL;
  *method_len = 0;
  *path = NULL;
  *path_len = 0;
  *minor_version = -1;
  *num_headers = 0;
  
  /* if last_len != 0, check if the request is complete (a fast countermeasure
     againt slowloris */
  if (last_len != 0 && is_complete(buf, buf_end, last_len, &r) == NULL) {
    return r;
  }
  
  if ((buf = parse_request(buf, buf_end, method, method_len, path, path_len,
			   minor_version, headers, num_headers, max_headers,
			   &r))
      == NULL) {
    return r;
  }
  
  return buf - buf_start;
}

static const char* parse_response(const char* buf, const char* buf_end,
				  int* minor_version, int* status,
				  const char** msg, size_t* msg_len,
				  struct phr_header* headers,
				  size_t* num_headers, size_t max_headers,
				  int* ret)
{
  /* parse "HTTP/1.x" */
  if ((buf = parse_http_version(buf, buf_end, minor_version, ret)) == NULL) {
    return NULL;
  }
  /* skip space */
  if (*buf++ != ' ') {
    *ret = -1;
    return NULL;
  }
  /* parse status code */
  if ((buf = parse_int(buf, buf_end, status, ret)) == NULL) {
    return NULL;
  }
  /* skip space */
  if (*buf++ != ' ') {
    *ret = -1;
    return NULL;
  }
  /* get message */
  if ((buf = get_token_to_eol(buf, buf_end, msg, msg_len, ret)) == NULL) {
    return NULL;
  }
  
  return parse_headers(buf, buf_end, headers, num_headers, max_headers, ret);
}

int phr_parse_response(const char* buf_start, size_t len, int* minor_version,
		       int* status, const char** msg, size_t* msg_len,
		       struct phr_header* headers, size_t* num_headers,
		       size_t last_len)
{
  const char * buf = buf_start, * buf_end = buf + len;
  size_t max_headers = *num_headers;
  int r;
  
  *minor_version = -1;
  *status = 0;
  *msg = NULL;
  *msg_len = 0;
  *num_headers = 0;
  
  /* if last_len != 0, check if the response is complete (a fast countermeasure
     against slowloris */
  if (last_len != 0 && is_complete(buf, buf_end, last_len, &r) == NULL) {
    return r;
  }
  
  if ((buf = parse_response(buf, buf_end, minor_version, status, msg, msg_len,
			    headers, num_headers, max_headers, &r))
      == NULL) {
    return r;
  }
  
  return buf - buf_start;
}

#undef CHECK_EOF
#undef EXPECT_CHAR
#undef ADVANCE_TOKEN



#ifndef STATIC_INLINE /* a public perl API from 5.13.4 */
#   if defined(__GNUC__) || defined(__cplusplus) || (defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L))
#       define STATIC_INLINE static inline
#   else
#       define STATIC_INLINE static
#   endif
#endif /* STATIC_INLINE */

#define MAX_HEADER_NAME_LEN 1024
#define MAX_HEADERS         128

#define HEADERS_NONE        0
#define HEADERS_AS_HASHREF  1
#define HEADERS_AS_ARRAYREF 2

STATIC_INLINE
char tou(char ch)
{
  if ('a' <= ch && ch <= 'z')
    ch -= 'a' - 'A';
  return ch;
}

STATIC_INLINE char tol(char const ch)
{
  return ('A' <= ch && ch <= 'Z')
    ? ch - ('A' - 'a')
    : ch;
}

/* copy src to dest with normalization.
   dest must have enough size for src */
STATIC_INLINE
void normalize_response_header_name(pTHX_
        char* const dest,
        const char* const src, STRLEN const len) {
    STRLEN i;
    for(i = 0; i < len; i++) {
        dest[i] = tol(src[i]);
    }
}

STATIC_INLINE
void concat_multiline_header(pTHX_ SV * val, const char * const cont, size_t const cont_len) {
    sv_catpvs(val, "\n"); /* XXX: is it collect? */
    sv_catpvn(val, cont, cont_len);
}

static
int header_is(const struct phr_header* header, const char* name,
		     size_t len)
{
  const char* x, * y;
  if (header->name_len != len)
    return 0;
  for (x = header->name, y = name; len != 0; --len, ++x, ++y)
    if (tou(*x) != *y)
      return 0;
  return 1;
}

static
size_t find_ch(const char* s, size_t len, char ch)
{
  size_t i;
  for (i = 0; i != len; ++i, ++s)
    if (*s == ch)
      break;
  return i;
}

STATIC_INLINE
int hex_decode(const char ch)
{
  int r;
  if ('0' <= ch && ch <= '9')
    r = ch - '0';
  else if ('A' <= ch && ch <= 'F')
    r = ch - 'A' + 0xa;
  else if ('a' <= ch && ch <= 'f')
    r = ch - 'a' + 0xa;
  else
    r = -1;
  return r;
}

static
char* url_decode(const char* s, size_t len)
{
  dTHX;
  char* dbuf, * d;
  size_t i;
  
  for (i = 0; i < len; ++i)
    if (s[i] == '%')
      goto NEEDS_DECODE;
  return (char*)s;
  
 NEEDS_DECODE:
  dbuf = (char*)malloc(len - 1);
  assert(dbuf != NULL);
  memcpy(dbuf, s, i);
  d = dbuf + i;
  while (i < len) {
    if (s[i] == '%') {
      int hi, lo;
      if ((hi = hex_decode(s[i + 1])) == -1
	  || (lo = hex_decode(s[i + 2])) == -1) {
        free(dbuf);
    	return NULL;
      }
      *d++ = hi * 16 + lo;
      i += 3;
    } else
      *d++ = s[i++];
  }
  *d = '\0';
  return dbuf;
}

STATIC_INLINE
int store_url_decoded(HV* env, const char* name, size_t name_len,
			       const char* value, size_t value_len)
{
  dTHX;
  char* decoded = url_decode(value, value_len);
  if (decoded == NULL)
    return -1;
  
  if (decoded == value)
    hv_store(env, name, name_len, newSVpvn(value, value_len), 0);
  else {
    hv_store(env, name, name_len, newSVpv(decoded, 0), 0);
    free(decoded);
  }
  return 0;
}



int
ngxe_parse_http_request_psgi(SV* buf, SV* envref) 
{
  const char* buf_str;
  STRLEN buf_len;
  const char* method;
  size_t method_len;
  const char* path;
  size_t path_len;
  int minor_version;
  struct phr_header headers[MAX_HEADERS];
  size_t num_headers, question_at;
  size_t i;
  int ret;
  HV* env;
  SV* last_value;
  char tmp[MAX_HEADER_NAME_LEN + sizeof("HTTP_") - 1];
  
  buf_str = SvPV(buf, buf_len);
  num_headers = MAX_HEADERS;
  ret = phr_parse_request(buf_str, buf_len, &method, &method_len, &path,
			  &path_len, &minor_version, headers, &num_headers, 0);
  if (ret < 0)
    goto done;
  
  env = (HV*)SvRV(envref);
 
  hv_store(env, "REQUEST_METHOD", sizeof("REQUEST_METHOD") - 1,
           newSVpvn(method, method_len), 0);
  hv_store(env, "REQUEST_URI", sizeof("REQUEST_URI") - 1,
	   newSVpvn(path, path_len), 0);
  hv_store(env, "SCRIPT_NAME", sizeof("SCRIPT_NAME") - 1, newSVpvn("", 0), 0);
  question_at = find_ch(path, path_len, '?');
  if (store_url_decoded(env, "PATH_INFO", sizeof("PATH_INFO") - 1, path,
			question_at)
      != 0) {
    hv_clear(env);
    ret = -1;
    goto done;
  }
  if (question_at != path_len)
    ++question_at;
  hv_store(env, "QUERY_STRING", sizeof("QUERY_STRING") - 1,
	   newSVpvn(path + question_at, path_len - question_at), 0);
  sprintf(tmp, "HTTP/1.%d", minor_version);
  hv_store(env, "SERVER_PROTOCOL", sizeof("SERVER_PROTOCOL") - 1,
           newSVpv(tmp, 0), 0);
  last_value = NULL;
  for (i = 0; i < num_headers; ++i) {
    if (headers[i].name != NULL) {
      const char* name;
      size_t name_len;
      SV** slot;
      if (header_is(headers + i, "CONTENT-TYPE", sizeof("CONTENT-TYPE") - 1)) {
	name = "CONTENT_TYPE";
	name_len = sizeof("CONTENT_TYPE") - 1;
      } else if (header_is(headers + i, "CONTENT-LENGTH",
			   sizeof("CONTENT-LENGTH") - 1)) {
	name = "CONTENT_LENGTH";
	name_len = sizeof("CONTENT_LENGTH") - 1;
      } else {
	const char* s;
	char* d;
	size_t n;
        if (sizeof(tmp) - 5 < headers[i].name_len) {
	  hv_clear(env);
          ret = -1;
          goto done;
        }
        strcpy(tmp, "HTTP_");
        for (s = headers[i].name, n = headers[i].name_len, d = tmp + 5;
	     n != 0;
	     s++, --n, d++)
          *d = *s == '-' ? '_' : tou(*s);
        name = tmp;
        name_len = headers[i].name_len + 5;
      }
      slot = hv_fetch(env, name, name_len, 1);
      if ( !slot ) {
        warn("failed to create hash entry");
	ret = -2;
	goto done;
      }
      if (SvOK(*slot)) {
        sv_catpvn(*slot, ", ", 2);
        sv_catpvn(*slot, headers[i].value, headers[i].value_len);
      } else
        sv_setpvn(*slot, headers[i].value, headers[i].value_len);
      last_value = *slot;
    } else {
      /* continuing lines of a mulitiline header */
      sv_catpvn(last_value, headers[i].value, headers[i].value_len);
    }
  }

done:

  return ret;
}


int
ngxe_parse_http_request(SV* buf, SV* envref) 
{
  const char* buf_str;
  STRLEN buf_len;
  const char* method;
  size_t method_len;
  const char* path;
  size_t path_len;
  int minor_version;
  struct phr_header headers[MAX_HEADERS];
  size_t num_headers, question_at;
  size_t i;
  int ret;
  HV* env;
  SV* last_value;
  char tmp[MAX_HEADER_NAME_LEN + sizeof("HTTP_") - 1];
  
  buf_str = SvPV(buf, buf_len);
  num_headers = MAX_HEADERS;
  ret = phr_parse_request(buf_str, buf_len, &method, &method_len, &path,
			  &path_len, &minor_version, headers, &num_headers, 0);
  if (ret < 0)
    goto done;
  
  env = (HV*)SvRV(envref);
 
  hv_store(env, "_method", sizeof("_method") - 1,
           newSVpvn(method, method_len), 0);
  hv_store(env, "_request_uri", sizeof("_request_uri") - 1,
	   newSVpvn(path, path_len), 0);

  question_at = find_ch(path, path_len, '?');
  if (store_url_decoded(env, "_path_info", sizeof("_path_info") - 1, path,
			question_at)
      != 0) {
    hv_clear(env);
    ret = -1;
    goto done;
  }
  if (question_at != path_len)
    ++question_at;
  hv_store(env, "_query_string", sizeof("_query_string") - 1,
	   newSVpvn(path + question_at, path_len - question_at), 0);
  sprintf(tmp, "HTTP/1.%d", minor_version);
  hv_store(env, "_protocol", sizeof("_protocol") - 1,
           newSVpv(tmp, 0), 0);
  last_value = NULL;
  for (i = 0; i < num_headers; ++i) {
    if (headers[i].name != NULL) {
      const char* name;
      size_t name_len;
      SV** slot;
      if (*(headers[i].name) == '_') {
	ret = -2;
	goto done;
      } else {
	const char* s;
	char* d;
	size_t n;
        if (sizeof(tmp) < headers[i].name_len) {
	  hv_clear(env);
          ret = -1;
          goto done;
        }
        for (s = headers[i].name, n = headers[i].name_len, d = tmp;
	     n != 0;
	     s++, --n, d++)
          *d = tol(*s);
        name = tmp;
        name_len = headers[i].name_len;
      }
      slot = hv_fetch(env, name, name_len, 1);
      if ( !slot ) {
        warn("failed to create hash entry");
	ret = -2;
	goto done;
      }
      if (SvOK(*slot)) {
        sv_catpvn(*slot, ", ", 2);
        sv_catpvn(*slot, headers[i].value, headers[i].value_len);
      } else
        sv_setpvn(*slot, headers[i].value, headers[i].value_len);
      last_value = *slot;
    } else {
      /* continuing lines of a mulitiline header */
      sv_catpvn(last_value, headers[i].value, headers[i].value_len);
    }
  }

done:

  return ret;
}



int
ngxe_parse_http_response(SV* buf, SV* envref) 
{
    int rv;



    return rv;
}



#if 0

void
parse_http_response(SV* buf, int header_format, HV* special_headers = NULL)
PPCODE:
{
  int minor_version, status;
  const char* msg;
  size_t msg_len;
  struct phr_header headers[MAX_HEADERS];
  size_t num_headers = MAX_HEADERS;
  STRLEN buf_len;
  const char* const buf_str = SvPV_const(buf, buf_len);
  size_t last_len = 0;
  int const ret             = phr_parse_response(buf_str, buf_len,
    &minor_version, &status, &msg, &msg_len, headers, &num_headers, last_len);
  SV* last_special_headers_value_sv = NULL;
  SV* last_element_value_sv         = NULL;
  size_t i;
  SV *res_headers;
  char name[MAX_HEADER_NAME_LEN]; /* temp buffer for normalized names */

  if (header_format == HEADERS_AS_HASHREF) {
    res_headers = sv_2mortal((SV*)newHV());
  } else if (header_format == HEADERS_AS_ARRAYREF) {
    res_headers = sv_2mortal((SV*)newAV());
    av_extend((AV*)res_headers, (num_headers * 2) - 1);
  } else if (header_format == HEADERS_NONE) {
    res_headers = NULL;
  }

  for (i = 0; i < num_headers; i++) {
    struct phr_header const h = headers[i];
    if (h.name != NULL) {
      SV* namesv;
      SV* valuesv;
      if(h.name_len > sizeof(name)) {
          /* skip if name_len is too long */
          continue;
      }

      normalize_response_header_name(aTHX_
        name, h.name, h.name_len);

      if(special_headers) {
          SV** const slot = hv_fetch(special_headers,
            name, h.name_len, FALSE);
          if (slot) {
            SV* const hash_value = *slot;
            sv_setpvn_mg(hash_value, h.value, h.value_len);
            last_special_headers_value_sv = hash_value;
          }
          else {
            last_special_headers_value_sv = NULL;
          }
      }

      if(header_format == HEADERS_NONE) {
          continue;
      }

      namesv  = sv_2mortal(newSVpvn_share(name, h.name_len, 0U));
      valuesv = newSVpvn_flags(
        h.value, h.value_len, SVs_TEMP);

      if (header_format == HEADERS_AS_HASHREF) {
        HE* const slot = hv_fetch_ent((HV*)res_headers, namesv, FALSE, 0U);
        if(!slot) { /* first time */
            (void)hv_store_ent((HV*)res_headers, namesv,
                SvREFCNT_inc_simple_NN(valuesv), 0U);
        }
        else { /* second time; the header has multiple values */
            SV* sv = hv_iterval((HV*)res_headers, slot);
            if(!( SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVAV )) {
                /* make $value to [$value] and restore it to $res_header */
                AV* const av    = newAV();
                SV* const avref = newRV_noinc((SV*)av);
                (void)av_store(av, 0, SvREFCNT_inc_simple_NN(sv));
                (void)hv_store_ent((HV*)res_headers, namesv, avref, 0U);
                sv = avref;
            }
            av_push((AV*)SvRV(sv), SvREFCNT_inc_simple_NN(valuesv));
        }
        last_element_value_sv = valuesv;
      } else if (header_format == HEADERS_AS_ARRAYREF) {
            av_push((AV*)res_headers, SvREFCNT_inc_simple_NN(namesv));
            av_push((AV*)res_headers, SvREFCNT_inc_simple_NN(valuesv));
            last_element_value_sv = valuesv;
      }
    } else {
      /* continuing lines of a mulitiline header */
      if (special_headers && last_special_headers_value_sv) {
        concat_multiline_header(aTHX_ last_special_headers_value_sv, h.value, h.value_len);
      }
      if ((header_format == HEADERS_AS_HASHREF || header_format == HEADERS_AS_ARRAYREF) && last_element_value_sv) {
        concat_multiline_header(aTHX_ last_element_value_sv, h.value, h.value_len);
      }
    }
  }
  
  if(ret > 0) {
    EXTEND(SP, 5);
    mPUSHi(ret);
    mPUSHi(minor_version);
    mPUSHi(status);
    mPUSHp(msg, msg_len);
    if (res_headers) {
      mPUSHs(newRV_inc(res_headers));
    } else {
      mPUSHs(&PL_sv_undef);
    }
  }
  else {
    EXTEND(SP, 1);
    mPUSHi(ret);
  }
}

#endif


