" SpellCheck.vim: Work with spelling errors.
"
" DEPENDENCIES:
"   - Requires Vim 7.0 or higher.
"   - SpellCheck.vim autoload script
"   - SpellCheck/quickfix.vim autoload script
"   - ingo/plugin/cmdcomplete.vim autoload script
"
" Copyright: (C) 2011-2015 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
"   2.00.011	10-Feb-2015	Extract g:SpellCheck_ErrorTypes; we need those
"				in SpellCheck#ParseArguments(), too.
"				ENH: Add g:SpellCheck_Predicates configuration.
"   2.00.010	09-Feb-2015	ENH: Make all commands take optional [bad | rare
"				| local | caps] type argument (the forwarded
"				[++opt] [file] accepted by some auxiliary
"				commands probably aren't very important here)
"				and use that for limiting the checks to those
"				spell error types.
"				Introduce g:SpellCheck_ConsideredErrorTypes
"				configuration variable to limit the error types
"				by default.
"   1.30.009	23-Jul-2014	Add configuration for highlighting of the error
"				word and context in the quickfix window.
"				Introduce additional
"				g:SpellCheck_SpellWordPattern because spell
"				checking doesn't exactly use the 'iskeyword'
"				option, and we have to emulate it.
"				FIX: Quickfix mappings are gone when closing and
"				reopening the quickfix window (:cclose | copen),
"				because a new scratch buffer is used, but the
"				autocmd BufRead quickfix has been cleared.
"				Only clear that autocmd when a different
"				quickfix source is used. (And then also turn off
"				the plugin's additional syntax highlighting.)
"   1.30.008	22-Jul-2014	Add configuration for error context.
"   1.21.007	23-Sep-2013	Add :NextUnlessSpellError and :NextOrSpellCheck
"				auxiliary commands.
"				Allow to pass optional [++opt] [file] arguments
"				to the :Write... commands.
"   1.20.006	08-May-2012	FIX: Line range is not defined and passed for
"				:BDeleteOrSpellCheck and other :...OrSpellCheck
"				commands, resulting in a script error.
"				ENH: Allow [range] for :BDeleteUnlessSpellError
"				and other :...UnlessSpellError commands, too.
"   1.12.005	01-May-2012	ENH: Allow [range] for :SpellCheck command.
"   1.10.004	30-Apr-2012	Add g:SpellCheck_OnSpellAdd hook.
"   1.00.003	06-Dec-2011	FIX: Missing :quit in :XitOrSpellCheck.
"	002	03-Dec-2011	Rename configvar to g:SpellCheck_OnNospell.
"	001	02-Dec-2011	file creation

" Avoid installing twice or when in unsupported Vim version.
if exists('g:loaded_SpellCheck') || (v:version < 700)
    finish
endif
let g:loaded_SpellCheck = 1
let s:save_cpo = &cpo
set cpo&vim

"- constants -------------------------------------------------------------------

let g:SpellCheck_ErrorTypes = ['bad', 'rare', 'local', 'caps']


"- configuration ---------------------------------------------------------------

if ! exists('g:SpellCheck_OnNospell')
    let g:SpellCheck_OnNospell = function('SpellCheck#AutoEnableSpell')
endif
if ! exists('g:SpellCheck_OnSpellAdd')
    let g:SpellCheck_OnSpellAdd = function('SpellCheck#SpellAddWrapper')
endif


if ! exists('g:SpellCheck_DefineAuxiliaryCommands')
    let g:SpellCheck_DefineAuxiliaryCommands = 1
endif
if ! exists('g:SpellCheck_DefineQuickfixMappings')
    let g:SpellCheck_DefineQuickfixMappings = 1
endif

if ! exists('g:SpellCheck_ErrorContextNum')
    let g:SpellCheck_ErrorContextNum = 99
endif

" From :help spellfile-cleanup:
"   Vim uses a fixed method to recognize a word.  This is independent of
"   'iskeyword', so that it also works in help files and for languages that
"   include characters like '-' in 'iskeyword'. [...]
"   The table with word characters is stored in the main .spl file.
" Since we cannot easily query that table, approximate the set of characters.
if ! exists('g:SpellCheck_SpellWordPattern')
    let g:SpellCheck_SpellWordPattern = '[[:alnum:]'']'
endif

if ! exists('g:SpellCheck_ErrorContextPattern')
    let g:SpellCheck_ErrorContextPattern = '\%(' . g:SpellCheck_SpellWordPattern . '*\%(' . g:SpellCheck_SpellWordPattern . '\@!\S\)\+\|' . g:SpellCheck_SpellWordPattern . '\+\s\+\)\?%s.' . g:SpellCheck_SpellWordPattern . '*\%(\%(' . g:SpellCheck_SpellWordPattern . '\@!\S\)\+' . g:SpellCheck_SpellWordPattern . '*\|\s\+' . g:SpellCheck_SpellWordPattern . '\+\)\?'
endif

if ! exists('g:SpellCheck_QuickfixHighlight')
    let g:SpellCheck_QuickfixHighlight = 1
endif

if ! exists('g:SpellCheck_ConsideredErrorTypes')
    let g:SpellCheck_ConsideredErrorTypes = []
endif
if ! exists('g:SpellCheck_Predicates')
    let g:SpellCheck_Predicates = ''
endif


"- mappings --------------------------------------------------------------------

if g:SpellCheck_DefineQuickfixMappings || g:SpellCheck_QuickfixHighlight
    augroup SpellCheckQuickfixMappings
	autocmd!
	" Note: Cannot use the QuickFixCmdPost event directly, as it does not
	" necessarily fire in the quickfix window! Fortunately, a BufRead event
	" for file "quickfix" is posted whenever a quickfix or location list
	" window is opened. (And the filetype is (re-)set afterwards, too.)
	" So, we use the QuickFixCmdPost event as a trigger to create the
	" mappings for the quickfix window when it is opened.
	autocmd QuickFixCmdPost spell,lspell
	\   let g:SpellCheck_IsQuickfixHighlightActive = g:SpellCheck_QuickfixHighlight |
	\   autocmd! SpellCheckQuickfixMappings BufRead quickfix
	\       if g:SpellCheck_DefineQuickfixMappings |
	\           call SpellCheck#mappings#MakeMappings() |
	\       endif
	" As a new scratch buffer is created whenever the quickfix window is
	" opened, the autocmd has to persist to embellish future ones (i.e.
	" after :cclose | :copen). But we stop embellishing when a different
	" quickfix source is used:
	autocmd QuickFixCmdPost *
	\   if expand('<afile>') !~# '^l\?spell' |
	\       let g:SpellCheck_IsQuickfixHighlightActive = 0 |
	\       execute 'autocmd! SpellCheckQuickfixMappings BufRead quickfix' |
	\   endif
    augroup END
endif


"- commands --------------------------------------------------------------------

call ingo#plugin#cmdcomplete#MakeFixedListCompleteFunc(g:SpellCheck_ErrorTypes, 'SpellCheckCompleteFunc')

if g:SpellCheck_DefineAuxiliaryCommands
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc BDeleteUnlessSpellError     if ! SpellCheck#CheckErrors(<line1>, <line2>, 0, <q-args>)      | bdelete<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc WriteUnlessSpellError       if ! SpellCheck#CheckErrors(<line1>, <line2>, 0, <q-args>)      | write<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc WriteDeleteUnlessSpellError if ! SpellCheck#CheckErrors(<line1>, <line2>, 0, <q-args>)      | write<bang> | bdelete<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc XitUnlessSpellError         if ! SpellCheck#CheckErrors(<line1>, <line2>, 0, <q-args>)      | write<bang> | quit<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc NextUnlessSpellError        if ! SpellCheck#CheckErrors(<line1>, <line2>, 0, <q-args>)      | next<bang> | endif

    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc BDeleteOrSpellCheck         if ! SpellCheck#quickfix#List(<line1>, <line2>, 0, 0, <q-args>) | bdelete<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc WriteOrSpellCheck           if ! SpellCheck#quickfix#List(<line1>, <line2>, 0, 0, <q-args>) | write<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc WriteDeleteOrSpellCheck     if ! SpellCheck#quickfix#List(<line1>, <line2>, 0, 0, <q-args>) | write<bang> | bdelete<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc XitOrSpellCheck             if ! SpellCheck#quickfix#List(<line1>, <line2>, 0, 0, <q-args>) | write<bang> | quit<bang> | endif
    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc NextOrSpellCheck            if ! SpellCheck#quickfix#List(<line1>, <line2>, 0, 0, <q-args>) | next<bang> | endif

    command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc UpdateAndSpellCheck         update<bang> | call SpellCheck#quickfix#List(<line1>, <line2>, 0, 0, <q-args>)
endif

command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc SpellCheck  call SpellCheck#quickfix#List(<line1>, <line2>, <bang>0, 0, <q-args>)
command! -bar -bang -range=% -nargs=* -complete=customlist,SpellCheckCompleteFunc SpellLCheck call SpellCheck#quickfix#List(<line1>, <line2>, <bang>0, 1, <q-args>)

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
