sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    out = {}
    for each p in m.top.paths
        out[p] = ServiceGet(p)
        m.top.results = out
    end for
end sub
