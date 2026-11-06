sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    out = {}
    for each r in m.top.requests
        p = r.params
        if p = invalid then p = {}
        resp = TmdbGet(r.endpoint, p)
        if resp.ok then
            out[r.key] = resp.data
            m.top.results = out
        else
            m.top.error = resp.error
        end if
    end for
end sub
