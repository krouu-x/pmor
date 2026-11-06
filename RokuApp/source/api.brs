' TMDB client (talks to the HTTPS proxy). MUST run on a Task thread (roUrlTransfer).
' Returns { ok: true, data: <AA> } or { ok: false, error: "<user friendly message>", code: <int> }
function TmdbGet(endpoint as string, params = {} as object) as object
    cfg = GetConfig()
    xfer = CreateObject("roUrlTransfer")

    query = ""
    keys = params.Keys()
    for each k in keys
        query += iif(query = "", "?", "&") + xfer.Escape(k) + "=" + xfer.Escape(params[k].ToStr())
    end for

    cacheKey = endpoint + query
    cached = CacheGet(cacheKey)
    if cached <> invalid then return { ok: true, data: cached, cached: true }

    ' Avoid duplicate in-flight work is handled by callers; cache covers repeats.
    if cfg.useProxy then
        xfer.SetUrl(cfg.proxyBaseUrl + endpoint + query)
    else
        xfer.SetUrl(cfg.directBaseUrl + endpoint + query)
        xfer.AddHeader("Authorization", "Bearer " + cfg.tmdbReadToken)
    end if
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.AddHeader("Accept", "application/json")
    xfer.EnableEncodings(true)
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)

    if not xfer.AsyncGetToString() then return { ok: false, code: -1, error: "Could not start the network request." }
    msg = wait(cfg.requestTimeoutMs, port)
    if msg = invalid then
        xfer.AsyncCancel()
        return { ok: false, code: -2, error: "The request timed out. Check your connection and try again." }
    end if

    code = msg.GetResponseCode()
    if code = 200 then
        data = ParseJson(msg.GetString())
        if data = invalid then return { ok: false, code: 200, error: "Received an unreadable response from the server." }
        CachePut(cacheKey, data, CacheTtlFor(endpoint))
        return { ok: true, data: data }
    end if

    return { ok: false, code: code, error: ApiErrorMessage(code) }
end function

function ApiErrorMessage(code as integer) as string
    if code < 0 then return "No internet connection. Please check your network."
    if code = 401 or code = 403 then return "The service rejected its credentials. Please contact the app owner."
    if code = 404 then return "That title could not be found."
    if code = 429 then return "Too many requests. Please wait a moment and try again."
    if code >= 500 then return "The metadata service is temporarily unavailable."
    return "Something went wrong (error " + code.ToStr() + ")."
end function


' Calls your local REST server (not cached). Returns { ok, data, code, latencyMs, error }.
function ServiceGet(path as string) as object
    cfg = GetConfig()
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(cfg.serviceBaseUrl + path)
    xfer.AddHeader("Accept", "application/json")
    if cfg.serviceToken <> "" then xfer.AddHeader("Authorization", "Bearer " + cfg.serviceToken)
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    clock = CreateObject("roTimespan")
    if not xfer.AsyncGetToString() then return { ok: false, code: -1, latencyMs: 0, error: "Could not start the request." }
    msg = wait(cfg.serviceTimeoutMs, port)
    ms = clock.TotalMilliseconds()
    if msg = invalid then
        xfer.AsyncCancel()
        return { ok: false, code: -2, latencyMs: ms, error: "Server did not answer in time (" + cfg.serviceBaseUrl + ")." }
    end if
    code = msg.GetResponseCode()
    if code >= 200 and code < 300 then
        data = ParseJson(msg.GetString())
        if data = invalid then data = { raw: msg.GetString() }
        return { ok: true, data: data, code: code, latencyMs: ms }
    end if
    return { ok: false, code: code, latencyMs: ms, error: ApiErrorMessage(code) }
end function
