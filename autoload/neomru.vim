"=============================================================================
" FILE: neomru.vim
" AUTHOR:  Zhao Cai <caizhaoff@gmail.com>
"          Shougo Matsushita <Shougo.Matsu at gmail.com>
" Last Modified: 18 Feb 2014.
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

let s:save_cpo = &cpo
set cpo&vim

function! neomru#set_default(var, val, ...)  "{{{
  if !exists(a:var) || type({a:var}) != type(a:val)
    let alternate_var = get(a:000, 0, '')

    let {a:var} = exists(alternate_var) ?
          \ {alternate_var} : a:val
  endif
endfunction"}}}
function! s:substitute_path_separator(path) "{{{
  return s:is_windows ? substitute(a:path, '\\', '/', 'g') : a:path
endfunction"}}}

" Variables  "{{{
" The version of MRU file format.
let s:VERSION = '0.3.0'

let s:is_windows = has('win16') || has('win32') || has('win64') || has('win95')

call neomru#set_default(
      \ 'g:neomru#do_validate', 1,
      \ 'g:unite_source_mru_do_validate')
call neomru#set_default(
      \ 'g:neomru#update_interval', 600,
      \ 'g:unite_source_mru_update_interval')
call neomru#set_default(
      \ 'g:neomru#time_format', '',
      \ 'g:unite_source_file_mru_time_format')
call neomru#set_default(
      \ 'g:neomru#filename_format', '',
      \ 'g:unite_source_file_mru_filename_format')
call neomru#set_default(
      \ 'g:neomru#file_mru_path',
      \ s:substitute_path_separator(
      \  expand('~/.cache/neomru/file')),
      \ 'g:unite_source_file_mru_file',)
call neomru#set_default(
      \ 'g:neomru#file_mru_limit',
      \ 1000, 'g:unite_source_file_mru_limit')
call neomru#set_default(
      \ 'g:neomru#file_mru_ignore_pattern',
      \'\~$\|\.\%(o\|exe\|dll\|bak\|zwc\|pyc\|sw[po]\)$'
      \'\|\%(^\|/\)\.\%(hg\|git\|bzr\|svn\)\%($\|/\)'
      \'\|^\%(\\\\\|/mnt/\|/media/\|/temp/\|/tmp/\|\%(/private\)\=/var/folders/\)'
      \'\|\%(^\%(fugitive\)://\)'
      \, 'g:unite_source_file_mru_ignore_pattern')

call neomru#set_default(
      \ 'g:neomru#directory_mru_path',
      \ s:substitute_path_separator(
      \  expand('~/.cache/neomru/directory')),
      \ 'g:unite_source_directory_mru_file')
call neomru#set_default(
      \ 'g:neomru#directory_mru_limit',
      \ 1000, 'g:unite_source_directory_mru_limit')
call neomru#set_default(
      \ 'g:neomru#directory_mru_ignore_pattern',
      \'\%(^\|/\)\.\%(hg\|git\|bzr\|svn\)\%($\|/\)'
      \'\|^\%(\\\\\|/mnt/\|/media/\|/temp/\|/tmp/\|\%(/private\)\=/var/folders/\)',
      \ 'g:unite_source_directory_mru_ignore_pattern')
"}}}

" MRUs  "{{{
let s:MRUs = {}

" Template MRU:  "{{{2
"---------------------%>---------------------
" @candidates:
" ------------
" [full_path, ... ]
"
" @mtime
" ------
" the last modified time of the mru file.
" - set once when loading the mru_file
" - update when #save()
"
" @is_loaded
" ----------
" 0: empty
" 1: loaded
" -------------------%<---------------------

let s:mru = {
      \ 'candidates'      : [],
      \ 'type'            : '',
      \ 'mtime'           : 0,
      \ 'update_interval' : g:neomru#update_interval,
      \ 'mru_file'        : '',
      \ 'limit'           : {},
      \ 'do_validate'     : g:neomru#do_validate,
      \ 'is_loaded'       : 0,
      \ 'version'         : s:VERSION,
      \ }

function! s:mru.is_a(type) "{{{
  return self.type == a:type
endfunction "}}}
function! s:mru.validate()
    throw 'unite(mru) umimplemented method: validate()!'
endfunction

function! s:mru.gather_candidates(args, context) "{{{
  if !self.is_loaded
    call self.load()
  endif

  if a:context.is_redraw && g:neomru#do_validate
    call self.reload()
  endif

  return map(copy(self.candidates), "{
        \ 'word' : v:val,
        \ 'action__path' : v:val,
        \}")
endfunction"}}}
function! s:mru.delete(candidates) "{{{
  for candidate in a:candidates
    call filter(self.candidates,
          \ 'v:val !=# candidate.action__path')
  endfor

  call self.save()
endfunction"}}}
function! s:mru.has_external_update() "{{{
  return self.mtime < getftime(self.mru_file)
endfunction"}}}

function! s:mru.save(...) "{{{
  let opts = {}
  if a:0 >= 1 && type(a:1) == type({})
    call extend(opts, a:1)
  endif

  if self.has_external_update() && filereadable(self.mru_file)
    " only need to get the list which contains the latest MRUs
    let [ver; items] = readfile(self.mru_file)
    if self.version_check(ver)
      call extend(self.candidates, items)
    endif
  endif

  let self.candidates = s:uniq(self.candidates)
  let self.candidates = self.candidates[: self.limit - 1]

  if get(opts, 'event') ==# 'VimLeavePre'
    call self.validate()
  endif

  call s:writefile(self.mru_file,
        \ [self.version] + self.candidates)

  let self.mtime = getftime(self.mru_file)
endfunction"}}}

function! s:mru.load(...)  "{{{
  let is_force = get(a:000, 0, 0)

  " everything is loaded, done!
  if !is_force && self.is_loaded && !self.has_external_update()
    return
  endif

  let mru_file = self.mru_file

  if !filereadable(mru_file)
    return
  endif

  let file = readfile(mru_file)
  if empty(file)
    return
  endif

  let [ver; items] = file
  if !self.version_check(ver)
    return
  endif

  " Assume properly saved and sorted. unique sort is not necessary here
  call extend(self.candidates, items)

  if self.is_loaded
    let self.candidates = s:uniq(self.candidates)
  endif

  let self.mtime = getftime(mru_file)
  let self.is_loaded = 1
endfunction"}}}
function! s:mru.reload()  "{{{
  call self.load(1)

  call filter(self.candidates,
        \ ((self.type == 'file') ?
        \ "s:is_file_exist(v:val)" : "isdirectory(v:val)"))
endfunction"}}}
function! s:mru.append(path)  "{{{
  call s:mru.load()
  let index = index(self.candidates, a:path)
  if index == 0
    return
  endif

  if index > 0
    call remove(self.candidates, index)
  endif
  call insert(self.candidates, a:path)

  let self.candidates = self.candidates[: self.limit - 1]
endfunction"}}}
function! s:mru.version_check(ver)  "{{{
  if str2float(a:ver) < self.version
    call s:print_error('Sorry, the version of MRU file is old.')
    return 0
  else
    return 1
  endif
endfunction"}}}

"}}}

" File MRU:   "{{{2
"
let s:file_mru = extend(deepcopy(s:mru), {
      \ 'type'          : 'file',
      \ 'mru_file'      : g:neomru#file_mru_path,
      \ 'limit'         : g:neomru#file_mru_limit,
      \ }
      \)
function! s:file_mru.validate()  "{{{
  if self.do_validate
    call filter(self.candidates, 's:is_file_exist(v:val)')
  endif
endfunction"}}}

" Directory MRU:   "{{{2
let s:directory_mru = extend(deepcopy(s:mru), {
      \ 'type'          : 'directory',
      \ 'mru_file'      : g:neomru#directory_mru_path,
      \ 'limit'         : g:neomru#directory_mru_limit,
      \ }
      \)

function! s:directory_mru.validate()  "{{{
  if self.do_validate
    call filter(self.candidates, 'getftype(v:val) ==# "dir"')
  endif
endfunction"}}}
"}}}

" Public Interface:   "{{{2

let s:MRUs.file = s:file_mru
let s:MRUs.directory = s:directory_mru
function! neomru#init()  "{{{
endfunction"}}}
function! neomru#_import_file(path) "{{{
  let path = a:path
  if path == ''
    let path = s:substitute_path_separator(
      \  expand('~/.unite/file_mru'))
  endif

  let s:file_mru.candidates = s:uniq(
        \ s:file_mru.candidates + s:import(path))
endfunction"}}}
function! neomru#_import_directory(path) "{{{
  let path = a:path
  if path == ''
    let path = s:substitute_path_separator(
          \  expand('~/.unite/directory_mru'))
  endif

  let s:directory_mru.candidates = s:uniq(
        \ s:directory_mru.candidates + s:import(path))
endfunction"}}}
function! neomru#_get_mrus()  "{{{
  return s:MRUs
endfunction"}}}
function! neomru#_append() "{{{
  if &l:buftype =~ 'help\|nofile'
    return
  endif

  let path = s:substitute_path_separator(expand('%:p'))
  if path !~ '\a\+:'
    let path = s:substitute_path_separator(
          \ simplify(resolve(path)))
  endif

  " Append the current buffer to the mru list.
  if s:is_file_exist(path)
    call s:file_mru.append(path)
  endif

  let filetype = getbufvar(bufnr('%'), '&filetype')
  if filetype ==# 'vimfiler' &&
        \ type(getbufvar(bufnr('%'), 'vimfiler')) == type({})
    let path = getbufvar(bufnr('%'), 'vimfiler').current_dir
  elseif filetype ==# 'vimshell' &&
        \ type(getbufvar(bufnr('%'), 'vimshell')) == type({})
    let path = getbufvar(bufnr('%'), 'vimshell').current_dir
  else
    let path = getcwd()
  endif

  let path = s:substitute_path_separator(simplify(resolve(path)))
  " Chomp last /.
  let path = substitute(path, '/$', '', '')

  " Append the current buffer to the mru list.
  if isdirectory(path)
    call s:directory_mru.append(path)
  endif
endfunction"}}}
function! neomru#_reload() "{{{
  for m in values(s:MRUs)
    call m.reload()
  endfor
endfunction"}}}
function! neomru#_save(...) "{{{
  let opts = {}
  if a:0 >= 1 && type(a:1) == type({})
    call extend(opts, a:1)
  endif

  for m in values(s:MRUs)
    call m.save(opts)
  endfor
endfunction"}}}
"}}}
"}}}

" Misc "{{{
function! s:writefile(path, list) "{{{
  if !isdirectory(fnamemodify(a:path, ':p:h'))
    call mkdir(fnamemodify(a:path, ':p:h'), 'p')
  endif

  call writefile(a:list, a:path)
endfunction"}}}
function! s:uniq(list, ...) "{{{
  return s:uniq_by(a:list, 'v:val')
endfunction"}}}
function! s:uniq_by(list, f) "{{{
  let list = map(copy(a:list), printf('[v:val, %s]', a:f))
  let i = 0
  let seen = {}
  while i < len(list)
    let key = string(list[i][1])
    if has_key(seen, key)
      call remove(list, i)
    else
      let seen[key] = 1
      let i += 1
    endif
  endwhile
  return map(list, 'v:val[0]')
endfunction"}}}
function! s:is_file_exist(path)  "{{{
  return a:path !~ '^\a\w\+:' && getftype(a:path) ==# 'file'
endfunction"}}}
function! s:import(path)  "{{{
  if !filereadable(a:path)
    call s:print_error(printf('path "%s" is not found.', a:path))
    return []
  endif

  let [ver; items] = readfile(a:path)
  let candidates = map(items, "split(v:val, '\t')[0]")
  " Load long file.
  if filereadable(a:path . '_long')
    let [ver; items] = readfile(a:path . '_long')
    let candidates += map(items, "split(v:val, '\t')[0]")
  endif

  return map(candidates, "substitute(v:val, '/$', '', '')")
endfunction"}}}
function! s:print_error(msg)  "{{{
  echohl Error | echomsg '[neomru] ' . a:msg | echohl None
endfunction"}}}
"}}}
"
let &cpo = s:save_cpo
unlet s:save_cpo

" vim: foldmethod=marker
