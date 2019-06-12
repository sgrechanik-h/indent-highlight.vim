" To make sure plugin is loaded only once,
" and to allow users to disable the plugin
" with a global conf.
if exists("g:do_not_load_indent_highlight")
  finish
endif
let g:do_not_load_indent_highlight = 1

if !exists("g:indent_highlight_bg_color")
  let g:indent_highlight_bg_color = 255
endif

function! s:InitHighlightGroup()
  " exe 'hi IndentHighlightGroup guibg=' . g:indent_highlight_bg_color . ' ctermbg=' . g:indent_highlight_bg_color
  exe 'hi IndentHighlightGroup ctermbg=' . g:indent_highlight_bg_color
endfunction

function! s:getStartDisabled()
  " Configuration to disable indent highlight when a buffer is opened.
  " This would allow users to enable it on demand.
  return get(g:, 'indent_highlight_start_disabled', 1)
endfunction

function! s:CurrentBlockIndentPattern(echoHeaderLine)
  let currentLineIndent = indent(".")
  " If the cursor is on the indentation space symbol, use its position to highlight indent
  if virtcol(".") < currentLineIndent
    let currentLineIndent = virtcol(".")
  endif
  let currentLineNumber = line(".")
  let startLineNumber = currentLineNumber
  let endNonEmptyLineNumber = currentLineNumber
  let endLineNumber = currentLineNumber
  let pattern = ""
  " When we use virtcol("."), this will be adjusted
  let indentLength = indent(".")

  while 1
    if !s:IsLineOfSameIndent(startLineNumber, currentLineIndent)
      " Print the header line
      if startLineNumber != currentLineNumber && a:echoHeaderLine
        echo getline(startLineNumber)
      endif
      break
    endif
    " TODO: This magic const should be a variable
    if startLineNumber < line("w0") - 100
      break
    endif
    if !empty(getline(startLineNumber)) && indent(startLineNumber) < indentLength
      let indentLength = indent(startLineNumber)
    endif
    let startLineNumber -= 1
  endwhile

  while s:IsLineOfSameIndent(endLineNumber, currentLineIndent)
    " TODO: This magic const should be a variable
    if endLineNumber > line("w$") + 20
      break
    endif
    if !empty(getline(endLineNumber))
      if indent(endLineNumber) < indentLength
        let indentLength = indent(endLineNumber)
      endif
      " This is needed to prevent highlighting of trailing newlines
      let endNonEmptyLineNumber = endLineNumber + 1
    endif
    let endLineNumber += 1
  endwhile

  let b:PreviousBlockStartLine = startLineNumber
  let b:PreviousBlockEndLine = endNonEmptyLineNumber
  let b:PreviousIndent = indentLength
  " Highlight just the indentation spaces and a bit of empty lines
  return '\%>' . startLineNumber . 'l\%<' . endNonEmptyLineNumber . 'l^\(' . repeat('\s', indentLength) . '\)\?'
endfunction

function! s:IsLineOfSameIndent(lineNumber, referenceIndent)
  " If currently on empty line, do not highlight anything
  if a:referenceIndent == 0
    return 0
  endif

  let lineIndent = indent(a:lineNumber)

  " lineNumber has crossed bounds.
  if lineIndent == -1
    return 0
  endif

  " Treat empty lines as current block
  if empty(getline(a:lineNumber))
    return 1
  endif

  " Treat lines with greater indent as current block
  if lineIndent >= a:referenceIndent
    return 1
  endif

  return 0
endfunction

function! RefreshIndentHighlightOnCursorMove()
  let echoHeaderLine = 0
  if exists("b:PreviousLine")
    if line('.') == b:PreviousLine
      let echoHeaderLine = 1
    endif
    " This is an exception to the whole subsequent logic: if we move inside the indentation columns,
    " perform highlighting
    if line('.') == b:PreviousLine && (virtcol('.') < b:PreviousIndent || b:PreviousIndent < indent('.'))
      call s:DoHighlight(echoHeaderLine)
      return
    endif
    " Do nothing if cursor has not moved to a new line unless the indent has changed or
    " the cursor is on the indentation space symbol or rehighlighting is needed
    if line('.') == b:PreviousLine && indent('.') == b:PreviousIndent && virtcol('.') >= b:PreviousIndent && !b:NeedsIndentRehighlightingOnTimeout
      return
    endif
    " If we are out of the previous block, stop highlighting it
    if line('.') < b:PreviousBlockStartLine || line('.') > b:PreviousBlockEndLine
      if get(w:, 'currentMatch', 0)
        call matchdelete(w:currentMatch)
        let w:currentMatch = 0
      endif
      " Rehighlight later
      let b:NeedsIndentRehighlightingOnTimeout = 1
    endif
    " If the line is empty, don't rehighlight, but change the PreviousLine
    if empty(getline('.'))
      let b:PreviousLine = line('.')
      return
    endif
    " Don't rehighlight too often
    " TODO: This magic const should be a variable
    if exists("b:PreviousIndentHighlightingTime") && reltimefloat(reltime(b:PreviousIndentHighlightingTime)) < 0.2
      " Prevent constant rehighlighting when scrolling
      let b:PreviousIndentHighlightingTime = reltime()
      " Rehighlight later
      let b:NeedsIndentRehighlightingOnTimeout = 1
      return
    endif
  endif
  call s:DoHighlight(echoHeaderLine)
endfunction

function! RefreshIndentHighlightOnCursorHold()
  if exists("b:NeedsIndentRehighlightingOnTimeout") && b:NeedsIndentRehighlightingOnTimeout
    " If the line is empty, don't rehighlight, but change the PreviousLine
    if empty(getline('.'))
      let b:PreviousLine = line('.')
      return
    endif
    call s:DoHighlight()
  endif
endfunction

function! RefreshIndentHighlightOnBufEnter()
  call s:DoHighlight()
endfunction

function! s:DoHighlight(...)
  let echoHeaderLine = get(a:, 0, 0)

  " Do nothing if indent_highlight_disabled is set globally or for window
  if get(g:, 'indent_highlight_disabled', 0) || get(b:, 'indent_highlight_disabled', s:getStartDisabled())
    return
  endif

  " Get the current block's pattern
  let pattern = s:CurrentBlockIndentPattern(echoHeaderLine)
  if empty(pattern)
    "Do nothing if no block pattern is recognized
    return
  endif

  " Clear previous highlight if it exists
  if get(w:, 'currentMatch', 0)
    call matchdelete(w:currentMatch)
    let w:currentMatch = 0
  endif

  " Highlight the new pattern
  let w:currentMatch = matchadd("IndentHighlightGroup", pattern)
  let b:PreviousLine = line('.')
  " let b:PreviousIndent = indent('.')
  let b:PreviousIndentHighlightingTime = reltime()
  let b:NeedsIndentRehighlightingOnTimeout = 0
endfunction

function! s:IndentHighlightHide()
  if get(w:, 'currentMatch', 0)
    call matchdelete(w:currentMatch)
    let w:currentMatch = 0
  endif
  let b:indent_highlight_disabled = 1
endfunction

function! s:IndentHighlightShow()
  let b:indent_highlight_disabled = 0
  call s:DoHighlight()
endfunction

function! s:IndentHighlightToggle()
  if get(b:, 'indent_highlight_disabled', s:getStartDisabled())
    call s:IndentHighlightShow()
  else
    call s:IndentHighlightHide()
  endif
endfunction

call s:InitHighlightGroup()

augroup indent_highlight
  autocmd!

  if !get(g:, 'indent_highlight_disabled', 0)
    " On cursor move, we check if line number has changed
    autocmd CursorMoved,CursorMovedI * call RefreshIndentHighlightOnCursorMove()
    " On timeout we check if we need to rehighlight
    autocmd CursorHold,CursorHoldI * call RefreshIndentHighlightOnCursorHold()
  endif

augroup END

" Default mapping is <Leader>ih
map <unique> <silent> <Leader>ih :IndentHighlightToggle<CR>

" If this command doesn't exist, create one.
" This is the only command available to the users.
if !exists(":IndentHighlightToggle")
  command IndentHighlightToggle  :call s:IndentHighlightToggle()
endif
