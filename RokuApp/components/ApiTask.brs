sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    params = m.top.params
    if params = invalid then params = {}
    r = TmdbGet(m.top.endpoint, params)
    if r.ok then
        m.top.result = r.data
    else
        m.top.error = r.error
    end if
end sub
