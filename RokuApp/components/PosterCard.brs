sub onContent()
    c = m.top.itemContent
    m.top.findNode("poster").uri = c.HDPosterUrl
    m.top.findNode("t").text = c.title
    m.top.findNode("s").text = c.ShortDescriptionLine1
end sub
