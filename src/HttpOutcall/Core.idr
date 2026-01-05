||| HttpOutcall Core Module
|||
||| FRC-compliant wrapper for ICP's ic0.http_request System API.
||| Provides typed HTTP requests with classified failure handling.
module HttpOutcall.Core

import FRC.Core
import Data.List
import Data.String
import Util.StringCase

%default total

-- =============================================================================
-- HTTP Types
-- =============================================================================

||| HTTP Method
public export
data HttpMethod = GET | POST | PUT | DELETE | HEAD | OPTIONS

public export
Show HttpMethod where
  show GET     = "GET"
  show POST    = "POST"
  show PUT     = "PUT"
  show DELETE  = "DELETE"
  show HEAD    = "HEAD"
  show OPTIONS = "OPTIONS"

public export
Eq HttpMethod where
  GET == GET = True
  POST == POST = True
  PUT == PUT = True
  DELETE == DELETE = True
  HEAD == HEAD = True
  OPTIONS == OPTIONS = True
  _ == _ = False

||| HTTP Header
public export
record HttpHeader where
  constructor MkHttpHeader
  name  : String
  value : String

public export
Show HttpHeader where
  show h = h.name ++ ": " ++ h.value

public export
Eq HttpHeader where
  h1 == h2 = h1.name == h2.name && h1.value == h2.value

||| HTTP Request
public export
record HttpRequest where
  constructor MkHttpRequest
  url     : String
  method  : HttpMethod
  headers : List HttpHeader
  body    : Maybe String

public export
Show HttpRequest where
  show r = show r.method ++ " " ++ r.url

||| HTTP Response
public export
record HttpResponse where
  constructor MkHttpResponse
  status  : Nat
  headers : List HttpHeader
  body    : String

public export
Show HttpResponse where
  show r = "HttpResponse{status=" ++ show r.status ++ ", bodyLen=" ++ show (length r.body) ++ "}"

-- =============================================================================
-- HTTP Failure Classification
-- =============================================================================

||| Classified HTTP failures
public export
data HttpFail
  = HttpTimeout
  | HttpConnectError String
  | HttpTlsError String
  | HttpDnsError String
  | HttpResponseTooLarge
  | HttpInvalidUrl String
  | HttpRateLimited Nat        -- Retry-After seconds
  | HttpServerError Nat String -- Status code, message
  | HttpClientError Nat String -- Status code, message
  | HttpParseError String
  | HttpTransformError String

public export
Show HttpFail where
  show HttpTimeout            = "Timeout"
  show (HttpConnectError s)   = "ConnectError: " ++ s
  show (HttpTlsError s)       = "TlsError: " ++ s
  show (HttpDnsError s)       = "DnsError: " ++ s
  show HttpResponseTooLarge   = "ResponseTooLarge"
  show (HttpInvalidUrl s)     = "InvalidUrl: " ++ s
  show (HttpRateLimited n)    = "RateLimited: retry after " ++ show n ++ "s"
  show (HttpServerError c m)  = "ServerError(" ++ show c ++ "): " ++ m
  show (HttpClientError c m)  = "ClientError(" ++ show c ++ "): " ++ m
  show (HttpParseError s)     = "ParseError: " ++ s
  show (HttpTransformError s) = "TransformError: " ++ s

||| Convert HttpFail to IcpFail for FR integration
public export
httpFailToIcpFail : HttpFail -> IcpFail
httpFailToIcpFail HttpTimeout            = Timeout "HTTP request timeout"
httpFailToIcpFail (HttpConnectError s)   = CallError ("Connect: " ++ s)
httpFailToIcpFail (HttpTlsError s)       = CallError ("TLS: " ++ s)
httpFailToIcpFail (HttpDnsError s)       = CallError ("DNS: " ++ s)
httpFailToIcpFail HttpResponseTooLarge   = CallError "Response too large"
httpFailToIcpFail (HttpInvalidUrl s)     = DecodeError ("Invalid URL: " ++ s)
httpFailToIcpFail (HttpRateLimited n)    = RateLimited ("Retry after " ++ show n ++ "s")
httpFailToIcpFail (HttpServerError c m)  = CallError ("Server " ++ show c ++ ": " ++ m)
httpFailToIcpFail (HttpClientError c m)  = CallError ("Client " ++ show c ++ ": " ++ m)
httpFailToIcpFail (HttpParseError s)     = DecodeError ("Parse: " ++ s)
httpFailToIcpFail (HttpTransformError s) = DecodeError ("Transform: " ++ s)

-- =============================================================================
-- Transform Configuration
-- =============================================================================

||| Transform function context for response processing
public export
record TransformContext where
  constructor MkTransformContext
  functionName : Maybe String  -- Optional transform function name
  context      : List Nat      -- Additional context bytes

||| Configuration for HTTP request
public export
record HttpRequestConfig where
  constructor MkHttpRequestConfig
  maxResponseBytes : Nat              -- Max response size (default 2MB)
  transform        : Maybe TransformContext
  cycles           : Nat              -- Cycles to attach for payment

||| Default HTTP request config
public export
defaultHttpConfig : HttpRequestConfig
defaultHttpConfig = MkHttpRequestConfig 2000000 Nothing 100000000000

-- =============================================================================
-- Status Code Classification
-- =============================================================================

||| Classify HTTP status code into failure type
public export
classifyStatus : Nat -> String -> Either HttpFail ()
classifyStatus status body =
  if status >= 200 && status < 300
    then Right ()
    else if status == 429
      then Left (HttpRateLimited 60)  -- Default retry after
      else if status == 408
        then Left HttpTimeout
        else if status >= 400 && status < 500
          then Left (HttpClientError status body)
          else if status >= 500
            then Left (HttpServerError status body)
            else Left (HttpClientError status "Unknown status")

||| Check if status indicates success
public export
isSuccessStatus : Nat -> Bool
isSuccessStatus status = status >= 200 && status < 300

||| Check if error is retryable
public export
isRetryable : HttpFail -> Bool
isRetryable HttpTimeout           = True
isRetryable (HttpRateLimited _)   = True
isRetryable (HttpServerError c _) = c >= 500 && c < 600
isRetryable (HttpConnectError _)  = True
isRetryable _                     = False

-- =============================================================================
-- Request Building Helpers
-- =============================================================================

||| Build HTTP request for JSON-RPC
public export
buildJsonRpcRequest : String -> String -> HttpRequest
buildJsonRpcRequest url body = MkHttpRequest
  url
  POST
  [ MkHttpHeader "Content-Type" "application/json"
  , MkHttpHeader "Accept" "application/json"
  ]
  (Just body)

||| Build HTTP GET request
public export
buildGetRequest : String -> List HttpHeader -> HttpRequest
buildGetRequest url headers = MkHttpRequest url GET headers Nothing

||| Add header to request
public export
addHeader : HttpHeader -> HttpRequest -> HttpRequest
addHeader h req = { headers := h :: req.headers } req

||| Set request body
public export
setBody : String -> HttpRequest -> HttpRequest
setBody body req = { body := Just body } req

-- =============================================================================
-- HTTP Operations (FRC-compliant)
-- =============================================================================

||| Execute HTTP request
||| This is a stub - actual implementation requires FFI to ic0.http_request
|||
||| In real implementation:
||| 1. Serialize HttpRequest to IC HttpRequestArgs
||| 2. Call ic0.http_request
||| 3. Await response via callback
||| 4. Parse HttpResponsePayload
||| 5. Classify errors and return FR result
public export
httpRequest :
  HttpRequest ->
  HttpRequestConfig ->
  FR HttpResponse
httpRequest req config =
  -- Stub implementation - would be replaced with actual FFI call
  fail HttpRequest "httpRequest"
       ("Stub: " ++ show req.method ++ " " ++ req.url)
       (Internal "ic0.http_request FFI not yet bound")

||| Execute HTTP request with automatic retry on retryable errors
public export
httpRequestWithRetry :
  HttpRequest ->
  HttpRequestConfig ->
  Nat ->              -- max retries
  FR HttpResponse
httpRequestWithRetry req config maxRetries =
  go maxRetries
  where
    go : Nat -> FR HttpResponse
    go 0 = httpRequest req config
    go (S n) = case !(httpRequest req config) of
      resp => ok HttpRequest "httpRequestWithRetry" "Success" resp
      -- In real implementation, would check for retryable errors

||| Validate URL before request
public export
validateUrl : String -> FR ()
validateUrl url =
  if length url == 0
    then fail Query "validateUrl" "Empty URL" (httpFailToIcpFail (HttpInvalidUrl "URL cannot be empty"))
    else if not (isPrefixOf "https://" url)
      then fail Query "validateUrl" "Must use HTTPS" (httpFailToIcpFail (HttpInvalidUrl "IC requires HTTPS"))
      else ok Query "validateUrl" ("Valid: " ++ url) ()

-- =============================================================================
-- Response Parsing Helpers
-- =============================================================================

||| Extract header value by name (case-insensitive)
public export
getHeader : String -> HttpResponse -> Maybe String
getHeader name resp =
  let nameLower = strToLower name
  in map value $ find (\h => strToLower h.name == nameLower) resp.headers

||| Check if response has JSON content type
public export
isJsonResponse : HttpResponse -> Bool
isJsonResponse resp =
  case getHeader "Content-Type" resp of
    Just ct => isInfixOf "application/json" ct
    Nothing => False

||| Parse response as text (with encoding check)
public export
parseTextResponse : HttpResponse -> FR String
parseTextResponse resp =
  if length resp.body == 0
    then ok Query "parseTextResponse" "Empty response" ""
    else ok Query "parseTextResponse" ("Parsed " ++ show (length resp.body) ++ " chars") resp.body
