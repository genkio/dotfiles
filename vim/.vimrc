filetype plugin on

syntax on

set nocompatible
set encoding=utf-8
set clipboard=unnamed
set rnu
set cursorline
set nowrap
set wildmenu
set hlsearch
set splitbelow
set splitright

set undofile
set undodir=~/.vim/undo

set autoindent
set smartindent
set tabstop=2
set softtabstop=2
set shiftwidth=2
set expandtab

noremap <C-h> <C-w>h
noremap <C-j> <C-w>j
noremap <C-k> <C-w>k
noremap <C-l> <C-w>l

noremap <silent> <Esc> :noh<CR><Esc>

command! RetabAll %retab!

function! TrimWhitespace()
    let l:save = winsaveview()
    %s/\s\+$//e
    %s/\n\+\%$//e
    call winrestview(l:save)
endfunction

autocmd BufWritePre * call TrimWhitespace()
