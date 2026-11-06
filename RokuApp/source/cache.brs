function CacheRoot() as string
    if CreateObject("roFileSystem").Exists("cachefs:/") then return "cachefs:/"
    return "tmp:/"
end function

function CachePath(key as string) as string
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(key)
    d = CreateObject("roEVPDigest")
    d.Setup("md5")
    return CacheRoot() + "tmdb_" + d.Process(ba) + ".json"
end function

function CacheNow() as integer
    return CreateObject("roDateTime").AsSeconds()
end function

function CacheGet(key as string) as dynamic
    txt = ReadAsciiFile(CachePath(key))
    if txt = "" then return invalid
    entry = ParseJson(txt)
    if entry = invalid then return invalid
    if entry.exp = invalid then return invalid
    if entry.exp < CacheNow() then return invalid
    return entry.data
end function

sub CachePut(key as string, data as object, ttl as integer)
    WriteAsciiFile(CachePath(key), FormatJson({ exp: CacheNow() + ttl, data: data }))
end sub

sub ClearCache()
    root = CacheRoot()
    for each f in ListDir(root)
        if Left(f, 5) = "tmdb_" then DeleteFile(root + f)
    end for
end sub

function CacheTtlFor(endpoint as string) as integer
    cfg = GetConfig()
    if Left(endpoint, 7) = "/search" then return cfg.ttlSearch
    for each w in ["/trending/", "/popular", "/top_rated", "/upcoming", "/on_the_air", "/now_playing"]
        if Instr(1, endpoint, w) > 0 then return cfg.ttlList
    end for
    return cfg.ttlDetail
end function

' ---- Watch history (registry, newest first, max 50) ----
function HistoryList() as object
    reg = CreateObject("roRegistrySection", "history")
    if reg.Exists("items") then
        l = ParseJson(reg.Read("items"))
        if l <> invalid then return l
    end if
    return []
end function

function HistoryFind(title as string) as dynamic
    for each x in HistoryList()
        if x.title = title then return x
    end for
    return invalid
end function

sub HistorySave(e as object)
    out = [e]
    for each x in HistoryList()
        if x.title <> e.title then out.push(x)
        if out.count() >= 50 then exit for
    end for
    reg = CreateObject("roRegistrySection", "history")
    reg.Write("items", FormatJson(out))
    reg.Flush()
end sub

' ---- Favorites (registry) ----
function FavList(mt as string) as object
    reg = CreateObject("roRegistrySection", "favorites")
    if reg.Exists(mt) then
        l = ParseJson(reg.Read(mt))
        if l <> invalid then return l
    end if
    return []
end function

function FavHas(mt as string, id as integer) as boolean
    for each f in FavList(mt)
        if f.tid = id then return true
    end for
    return false
end function

function FavToggle(mt as string, entry as object) as boolean
    out = []
    found = false
    for each f in FavList(mt)
        if f.tid = entry.tid then
            found = true
        else
            out.push(f)
        end if
    end for
    if not found then out.push(entry)
    reg = CreateObject("roRegistrySection", "favorites")
    reg.Write(mt, FormatJson(out))
    reg.Flush()
    return not found
end function
