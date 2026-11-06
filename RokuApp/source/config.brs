' Central configuration. Set proxyBaseUrl to your deployed proxy (HTTPS, no trailing slash).
function GetConfig() as object
    cfg = {
        useProxy: false
        serviceBaseUrl: "http://192.168.0.11:8787"
        serviceToken: ""
        serviceTimeoutMs: 30000
        proxyBaseUrl: "https://YOUR-PROXY-HOST/tmdb"
        directBaseUrl: "https://api.themoviedb.org/3"
        ' Stream proxy for playing videos with required headers
        streamProxyBaseUrl: "http://192.168.0.11:8788"
        ' PERSONAL/SIDELOAD USE ONLY: these ship inside the .zip and can be extracted.
        tmdbReadToken: "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI1YjFjM2M4ZDg3MTU1MWU2NDg0N2FlNGQ5NTRlMDgwNyIsIm5iZiI6MTc4NjU2MTM5Ni43OTMsInN1YiI6IjZhN2NjMzc0ZmI3YTFjMjkwMTQ0ZmRlYSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.heOiSMRVHPZiCerBZK-91bqtqclEDjCbnzbYpFQo56w"
        tmdbApiKey: "5b1c3c8d871551e64847ae4d954e0807"
        imageBase: "https://image.tmdb.org/t/p/"
        imageSizes: { poster: "w342", posterSmall: "w185", backdrop: "w780", still: "w500", full: "original" }
        requestTimeoutMs: 15000
        ttlList: 21600      ' 6 hours: trending/popular/etc.
        ttlDetail: 86400    ' 24 hours: details/credits/seasons
        ttlSearch: 600      ' 10 minutes
        attribution: "This product uses the TMDB API but is not endorsed or certified by TMDB."
    }
    saved = SavedServerUrl()
    if saved <> "" then cfg.serviceBaseUrl = saved
    return cfg
end function

function ImageUrl(path as dynamic, kind = "poster" as string) as string
    if path = invalid or path = "" then return ""
    cfg = GetConfig()
    return cfg.imageBase + cfg.imageSizes[kind] + path
end function

function iif(cond as boolean, a as dynamic, b as dynamic) as dynamic
    if cond then return a
    return b
end function

' ---- Server address override (saved in the registry, editable in Settings) ----
function SavedServerUrl() as string
    reg = CreateObject("roRegistrySection", "settings")
    if reg.Exists("serviceUrl") then return reg.Read("serviceUrl")
    return ""
end function

sub SaveServerUrl(url as string)
    reg = CreateObject("roRegistrySection", "settings")
    if url = "" then
        reg.Delete("serviceUrl")
    else
        reg.Write("serviceUrl", url)
    end if
    reg.Flush()
end sub

' "192.168.43.1" or "192.168.43.1:9000" or "http://host:port" -> "http://host:port"
function NormalizeServerUrl(input as string) as string
    u = input.Trim()
    if u = "" then return ""
    if Left(LCase(u), 4) <> "http" then u = "http://" + u
    while Right(u, 1) = "/"
        u = Left(u, Len(u) - 1)
    end while
    ' Do NOT auto-add port 8787 - let user specify or use standard ports (80/443)
    ' If user wants custom port, they include it in the URL (e.g., https://host:8787)
    return u
end function