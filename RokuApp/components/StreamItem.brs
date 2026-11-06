sub init()
    m.bg = m.top.findNode("bg")
    m.focusBg = m.top.findNode("focusBg")
    m.titleLabel = m.top.findNode("titleLabel")
end sub

sub onItemContentChange()
    if m.top.itemContent <> invalid then
        m.titleLabel.text = m.top.itemContent.title
    end if
end sub

sub onFocusRender()
    m.focusBg.opacity = 1.0
end sub

sub onBlurRender()
    m.focusBg.opacity = 0.0
end sub