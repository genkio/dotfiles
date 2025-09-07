"\" enable filetype detection and language-specific indentation
filetype plugin on

syntax on

set nocompatible " for vim only
set encoding=utf-8
set clipboard=unnamed " yank to clipboard (macos only)
set rnu
set wrap
set wildmenu
set hlsearch
set splitbelow
set splitright

set autoindent
set tabstop=8       " how many spaces a <Tab> counts for (display)
set softtabstop=2   " how many spaces <Tab> inserts when editing
set shiftwidth=2    " indentation width
set expandtab       " use spaces instead of literal tabs

" shortcutting split navigation (avoid C-w)
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" <Esc> also clear search highlights
nnoremap <silent> <Esc> :noh<CR><Esc>

" :RetabAll to replace ALL tabs with spaces using current settings
command! RetabAll %retab!

" remove trailing whitespaces and empty lines at the end of the file on save
function! TrimWhitespace()
    let l:save = winsaveview()
    %s/\s\+$//e
    %s/\n\+\%$//e
    call winrestview(l:save)
endfunction

autocmd BufWritePre * call TrimWhitespace()
