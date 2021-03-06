" Part of Vim filetype plugin for Clojure
" Language:     Clojure
" Maintainer:   Meikel Brandmeyer <mb@kotka.de>

let s:save_cpo = &cpo
set cpo&vim

function! vimclojure#SynIdName()
	return synIDattr(synID(line("."), col("."), 0), "name")
endfunction

function! vimclojure#WithSaved(closure)
	let v = a:closure.get(a:closure.tosafe)
	try
		let r = a:closure.f()
	finally
		call a:closure.set(a:closure.tosafe, v)
	endtry
	return r
endfunction

function! vimclojure#WithSavedPosition(closure)
	let a:closure['tosafe'] = "."
	let a:closure['get'] = function("getpos")
	let a:closure['set'] = function("setpos")
	return vimclojure#WithSaved(a:closure)
endfunction

function! vimclojure#WithSavedRegister(closure)
	let a:closure['get'] = function("getreg")
	let a:closure['set'] = function("setreg")
	return vimclojure#WithSaved(a:closure)
endfunction

function! vimclojure#WithSavedOption(closure)
	function a:closure.get(option)
		execute "let val = &" . a:option
		return val
	endfunction

	function a:closure.set(option, value)
		execute "let &" . a:option . " = a:value"
	endfunction

	return vimclojure#WithSaved(a:closure)
endfunction

function! vimclojure#Yank(r, how)
	let closure = {'tosafe': a:r, 'yank': a:how}

	function closure.f() dict
		silent execute self.yank
		return getreg(self.tosafe)
	endfunction

	return vimclojure#WithSavedRegister(closure)
endfunction

function! vimclojure#EscapePathForOption(path)
	let path = fnameescape(a:path)

	" Hardcore escapeing of whitespace...
	let path = substitute(path, '\', '\\\\', 'g')
	let path = substitute(path, '\ ', '\\ ', 'g')

	return path
endfunction

function! vimclojure#AddPathToOption(path, option)
	let path = vimclojure#EscapePathForOption(a:path)
	execute "setlocal " . a:option . "+=" . path
endfunction

function! vimclojure#AddCompletions(ns)
	let completions = split(globpath(&rtp, "ftplugin/clojure/completions-" . a:ns . ".txt"), '\n')
	if completions != []
		call vimclojure#AddPathToOption('k' . completions[0], 'complete')
	endif
endfunction

" Nailgun part:
function! vimclojure#ExtractSexpr(toplevel)
	let closure = { "flag" : (a:toplevel ? "r" : "") }

	function closure.f() dict
		if searchpairpos('(', '', ')', 'bW' . self.flag,
					\ 'vimclojure#SynIdName() !~ "clojureParen\\d"') != [0, 0]
			return vimclojure#Yank('l', 'normal! "ly%')
		end
		return ""
	endfunction

	return vimclojure#WithSavedPosition(closure)
endfunction

function! vimclojure#BufferName()
	let file = expand("%")
	if file == ""
		let file = "UNNAMED"
	endif
	return file
endfunction

" Key mappings and Plugs
function! vimclojure#MakePlug(mode, plug, f)
	execute a:mode . "noremap <Plug>Clojure" . a:plug
				\ . " :call " . a:f . "<CR>"
endfunction

function! vimclojure#MapPlug(mode, keys, plug)
	if !hasmapto("<Plug>Clojure" . a:plug)
		execute a:mode . "map <buffer> <unique> <silent> <LocalLeader>" . a:keys
					\ . " <Plug>Clojure" . a:plug
	endif
endfunction

" A Buffer...
if !exists("vimclojure#SplitPos")
	let vimclojure#SplitPos = "top"
endif

let vimclojure#Buffer = {}

function! vimclojure#Buffer.New() dict
	let instance = copy(self)

	call self.MakeBuffer()
	call self.Init(instance)

	return instance
endfunction

function! vimclojure#Buffer.MakeBuffer()
	if g:vimclojure#SplitPos == "left" || g:vimclojure#SplitPos == "right"
		let o_sr = &splitright
		if g:vimclojure#SplitPos == "left"
			set nosplitright
		else
			set splitright
		end
		vnew
		let &splitright = o_sr
	else
		let o_sb = &splitbelow
		if g:vimclojure#SplitPos == "bottom"
			set splitbelow
		else
			set nosplitbelow
		end
		new
		let &splitbelow = o_sb
	endif
endfunction

function! vimclojure#Buffer.Init(instance)
	let a:instance._buffer = bufnr("%")
endfunction

function! vimclojure#Buffer.goHere() dict
	execute "buffer! " . self._buffer
endfunction

function! vimclojure#Buffer.resize() dict
	call self.goHere()
	let size = line("$")
	if size < 3
		let size = 3
	endif
	execute "resize " . size
endfunction

function! vimclojure#Buffer.showText(text) dict
	call self.goHere()
	if type(a:text) == type("")
		let text = split(a:text, '\n')
	else
		let text = a:text
	endif
	call append(line("$"), text)
endfunction

function! vimclojure#Buffer.close() dict
	execute "bdelete! " . self._buffer
endfunction

" The transient buffer, used to display results.
let vimclojure#ResultBuffer = copy(vimclojure#Buffer)
let vimclojure#ResultBuffer["__superBufferInit"] = vimclojure#ResultBuffer["Init"]
let vimclojure#ResultBuffer.__instance = []

function! vimclojure#ResultBuffer.New() dict
	if g:vimclojure#ResultBuffer.__instance != []
		return self.Init(g:vimclojure#ResultBuffer.__instance[0])
	endif

	let instance = copy(self)
	let g:vimclojure#ResultBuffer.__instance = [ instance ]

	call g:vimclojure#Buffer.MakeBuffer()
	call self.__superBufferInit(instance)
	call self.Init(instance)

	return instance
endfunction

function! vimclojure#ResultBuffer.Init(instance) dict
	setlocal noswapfile
	setlocal buftype=nofile
	setlocal bufhidden=wipe

	call vimclojure#MapPlug("n", "p", "CloseResultBuffer")

	let leader = exists("g:maplocalleader") ? g:maplocalleader : "\\"

	1
	normal! "_dG

	call append(0, "; Use " . leader . "p to close this buffer!")

	return a:instance
endfunction

function! vimclojure#ResultBuffer.CloseBuffer() dict
	if g:vimclojure#ResultBuffer.__instance != []
		let instance = g:vimclojure#ResultBuffer.__instance[0]
		let g:vimclojure#ResultBuffer.__instance = []
		call instance.close()
	endif
endfunction

" A special result buffer for clojure output.
let vimclojure#ClojureResultBuffer = copy(vimclojure#ResultBuffer)
let vimclojure#ClojureResultBuffer["__superResultBufferInit"] =
			\ vimclojure#ResultBuffer["Init"]

function! vimclojure#ClojureResultBuffer.Init(instance) dict
	call self.__superResultBufferInit(a:instance)
	setfiletype clojure

	return a:instance
endfunction

" Nails
if !exists("vimclojure#NailgunClient")
	let vimclojure#NailgunClient = "ng"
endif

function! vimclojure#ShellEscapeArguments(vals)
	let closure = { 'vals': a:vals, 'tosafe': 'shellslash' }

	function closure.f() dict
		set noshellslash
		return map(copy(self.vals), 'shellescape(v:val)')
	endfunction

	return vimclojure#WithSavedOption(closure)
endfunction

function! vimclojure#ExecuteNailWithInput(nail, input, ...)
	if type(a:input) == type("")
		let input = split(a:input, '\n', 1)
	else
		let input = a:input
	endif

	let inputfile = tempname()
	try
		call writefile(input, inputfile)

		let cmdline = [g:vimclojure#NailgunClient,
					\ "de.kotka.vimclojure.nails." . a:nail]
					\ + vimclojure#ShellEscapeArguments(a:000)
		let cmd = join(cmdline, " ") . " <" . inputfile

		let result = system(cmd)

		if v:shell_error
			echoerr "Couldn't execute Nail! "
						\ . substitute(result, '\n\(\t\?\)', ' ', 'g')
		endif
	finally
		call delete(inputfile)
	endtry

	return substitute(result, '\n$', '', '')
endfunction

function! vimclojure#ExecuteNail(nail, ...)
	return call(function("vimclojure#ExecuteNailWithInput"), [a:nail, ""] + a:000)
endfunction

function! vimclojure#FilterNail(nail, rngStart, rngEnd, ...)
	let cmdline = [g:vimclojure#NailgunClient,
				\ "de.kotka.vimclojure.nails." . a:nail]
				\ + vimclojure#ShellEscapeArguments(a:000)
	let cmd = a:rngStart . "," . a:rngEnd . "!" . join(cmdline, " ")

	silent execute cmd
endfunction

function! vimclojure#DocLookup(word)
	let docs = vimclojure#ExecuteNailWithInput("DocLookup", a:word,
				\ "-n", b:vimclojure_namespace)
	let resultBuffer = g:vimclojure#ResultBuffer.New()
	call resultBuffer.showText(docs)
	wincmd p
endfunction

function! vimclojure#FindDoc()
	let pattern = input("Pattern to look for: ")
	let result = vimclojure#ExecuteNailWithInput("FindDoc", pattern)

	let resultBuffer = g:vimclojure#ResultBuffer.New()
	call resultBuffer.showText(result)

	wincmd p
endfunction

let s:DefaultJavadocPaths = {
			\ "java" : "http://java.sun.com/javase/6/docs/api/",
			\ "org/apache/commons/beanutils" : "http://commons.apache.org/beanutils/api/",
			\ "org/apache/commons/chain" : "http://commons.apache.org/chain/api-release/",
			\ "org/apache/commons/cli" : "http://commons.apache.org/cli/api-release/",
			\ "org/apache/commons/codec" : "http://commons.apache.org/codec/api-release/",
			\ "org/apache/commons/collections" : "http://commons.apache.org/collections/api-release/",
			\ "org/apache/commons/logging" : "http://commons.apache.org/logging/apidocs/",
			\ "org/apache/commons/mail" : "http://commons.apache.org/email/api-release/",
			\ "org/apache/commons/io" : "http://commons.apache.org/io/api-release/"
			\ }

if !exists("vimclojure#JavadocPathMap")
	let vimclojure#JavadocPathMap = {}
endif

for k in keys(s:DefaultJavadocPaths)
	if !has_key(vimclojure#JavadocPathMap, k)
		let vimclojure#JavadocPathMap[k] = s:DefaultJavadocPaths[k]
	endif
endfor

if !exists("vimclojure#Browser")
	if has("win32") || has("win64")
		let vimclojure#Browser = "start"
	elseif has("mac")
		let vimclojure#Browser = "open"
	else
		let vimclojure#Browser = "firefox -new-window"
	endif
endif

function! vimclojure#JavadocLookup(word)
	let word = substitute(a:word, "\\.$", "", "")
	let path = vimclojure#ExecuteNailWithInput("JavadocPath", word,
				\ "-n", b:vimclojure_namespace)

	let match = ""
	for pattern in keys(g:vimclojure#JavadocPathMap)
		if path =~ "^" . pattern && len(match) < len(pattern)
			let match = pattern
		endif
	endfor

	if match == ""
		throw "No matching Javadoc URL found for " . path
	endif

	let url = g:vimclojure#JavadocPathMap[match] . path
	call system(join([g:vimclojure#Browser, url], " "))
endfunction

function! vimclojure#MetaLookup(word)
	let docs = vimclojure#ExecuteNailWithInput("MetaLookup", a:word,
				\ "-n", b:vimclojure_namespace)
	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(docs)
	wincmd p
endfunction

function! vimclojure#SourceLookup(word)
	let source = vimclojure#ExecuteNailWithInput("SourceLookup", a:word,
				\ "-n", b:vimclojure_namespace)
	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(source)
	wincmd p
endfunction

function! vimclojure#GotoSource(word)
	let result = vimclojure#ExecuteNailWithInput("SourceLocation", a:word,
				\ "-n", b:vimclojure_namespace)
	execute "let pos = " . result

	if !filereadable(pos.file)
		let file = findfile(pos.file)
		if file == ""
			echoerr pos.file . " not found in 'path'"
			return
		endif
		let pos.file = file
	endif

	execute "edit " . pos.file
	execute pos.line
endfunction

" Evaluators
function! vimclojure#MacroExpand(firstOnly)
	let sexp = vimclojure#ExtractSexpr(0)
	let ns = b:vimclojure_namespace

	let cmd = ["MacroExpand", sexp, "-n", ns]
	if a:firstOnly
		let cmd = cmd + [ "-o" ]
	endif

	let result = call(function("vimclojure#ExecuteNailWithInput"), cmd)

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

function! vimclojure#RequireFile(all)
	let ns = b:vimclojure_namespace
	let all = a:all ? "-all" : ""

	let require = "(require :reload" . all . " :verbose '". ns. ")"
	let result = vimclojure#ExecuteNailWithInput("Repl", require, "-r")

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

function! vimclojure#RunTests(all)
	let ns = b:vimclojure_namespace
	let all = a:all ? "-all" : ""

	let cmd = ""
	if ns != "user"
		let cmd .= "(require :reload" . all . " '" . ns . ")"
	endif
	let cmd .= "(require 'clojure.contrib.test-is)"
	let cmd .= "(clojure.contrib.test-is/run-tests (find-ns '" . ns ."))"
	let result = vimclojure#ExecuteNailWithInput("Repl", cmd, "-r")

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

function! vimclojure#EvalFile()
	let content = getbufline(bufnr("%"), 1, line("$"))
	let file = vimclojure#BufferName()
	let ns = b:vimclojure_namespace

	let result = vimclojure#ExecuteNailWithInput("Repl", content,
				\ "-r", "-n", ns, "-f", file)

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

function! vimclojure#EvalLine()
	let theLine = line(".")
	let content = getline(theLine)
	let file = vimclojure#BufferName()
	let ns = b:vimclojure_namespace

	let result = vimclojure#ExecuteNailWithInput("Repl", content,
				\ "-r", "-n", ns, "-f", file, "-l", theLine)

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

function! vimclojure#EvalBlock() range
	let file = vimclojure#BufferName()
	let ns = b:vimclojure_namespace

	let content = getbufline(bufnr("%"), a:firstline, a:lastline)
	let result = vimclojure#ExecuteNailWithInput("Repl", content,
				\ "-r", "-n", ns, "-f", file, "-l", a:firstline - 1)

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

function! vimclojure#EvalToplevel()
	let file = vimclojure#BufferName()
	let ns = b:vimclojure_namespace

	let pos = searchpairpos('(', '', ')', 'bWnr',
					\ 'vimclojure#SynIdName() !~ "clojureParen\\d"')

	if pos == [0, 0]
		throw "Error: Not in toplevel expression!"
	endif

	let expr = vimclojure#ExtractSexpr(1)
	let result = vimclojure#ExecuteNailWithInput("Repl", expr,
				\ "-r", "-n", ns, "-f", file, "-l", pos[0] - 1)

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

function! vimclojure#EvalParagraph()
	let file = vimclojure#BufferName()
	let ns = b:vimclojure_namespace
	let startPosition = line(".")

	let closure = {}

	function! closure.f() dict
		normal! }
		return line(".")
	endfunction

	let endPosition = vimclojure#WithSavedPosition(closure)

	let content = getbufline(bufnr("%"), startPosition, endPosition)
	let result = vimclojure#ExecuteNailWithInput("Repl", content,
				\ "-r", "-n", ns, "-f", file, "-l", startPosition - 1)

	let resultBuffer = g:vimclojure#ClojureResultBuffer.New()
	call resultBuffer.showText(result)
	wincmd p
endfunction

" The Repl
let vimclojure#Repl = copy(vimclojure#Buffer)
let vimclojure#Repl.__superBufferInit = vimclojure#Repl.Init

let vimclojure#Repl._prompt = "user=>"
let vimclojure#Repl._history = []
let vimclojure#Repl._historyDepth = 0
let vimclojure#Repl._replCommands = [ ",close", ",st", ",ct" ]

function! vimclojure#Repl.New() dict
	let instance = copy(self)

	call g:vimclojure#Buffer.MakeBuffer()
	call self.Init(instance)

	return instance
endfunction

function! vimclojure#Repl.Init(instance) dict
	call self.__superBufferInit(a:instance)

	setlocal buftype=nofile
	setlocal noswapfile

	if !hasmapto("<Plug>ClojureReplEnterHook")
		imap <buffer> <silent> <CR> <Plug>ClojureReplEnterHook
	endif
	if !hasmapto("<Plug>ClojureReplUpHistory")
		imap <buffer> <silent> <C-Up> <Plug>ClojureReplUpHistory
	endif
	if !hasmapto("<Plug>ClojureReplDownHistory")
		imap <buffer> <silent> <C-Down> <Plug>ClojureReplDownHistory
	endif

	call append(line("$"), ["Clojure", self._prompt . " "])

	let a:instance._id = vimclojure#ExecuteNail("Repl", "-s")
	call vimclojure#ExecuteNailWithInput("Repl",
				\ "(require 'clojure.stacktrace)", "-r",
				\ "-i", a:instance._id)

	let b:vimclojure_repl = a:instance

	setfiletype clojure

	normal! G
	startinsert!
endfunction

function! vimclojure#Repl.isReplCommand(cmd) dict
	for candidate in self._replCommands
		if candidate == a:cmd
			return 1
		endif
	endfor
	return 0
endfunction

function! vimclojure#Repl.doReplCommand(cmd) dict
	if a:cmd == ",close"
		call vimclojure#ExecuteNail("Repl", "-S", "-i", self._id)
		call self.close()
		stopinsert
	elseif a:cmd == ",st"
		let result = vimclojure#ExecuteNailWithInput("Repl",
					\ "(clojure.stacktrace/print-stack-trace *e)", "-r",
					\ "-i", self._id)
		call self.showText(result)
		call self.showPrompt()
	elseif a:cmd == ",ct"
		let result = vimclojure#ExecuteNailWithInput("Repl",
					\ "(clojure.stacktrace/print-cause-trace *e)", "-r",
					\ "-i", self._id)
		call self.showText(result)
		call self.showPrompt()
	endif
endfunction

function! vimclojure#Repl.showPrompt() dict
	call self.showText(self._prompt . " ")
	normal! G
	startinsert!
endfunction

function! vimclojure#Repl.getCommand() dict
	let ln = line("$")

	while getline(ln) !~ "^" . self._prompt && ln > 0
		let ln = ln - 1
	endwhile

	" Special Case: User deleted Prompt by accident. Insert a new one.
	if ln == 0
		call self.showPrompt()
		return ""
	endif

	let cmd = vimclojure#Yank("l", ln . "," . line("$") . "yank l")

	let cmd = substitute(cmd, "^" . self._prompt . "\\s*", "", "")
	let cmd = substitute(cmd, "\n$", "", "")
	return cmd
endfunction

function! vimclojure#Repl.enterHook() dict
	let cmd = self.getCommand()

	" Special Case: Showed prompt (or user just hit enter).
	if cmd == ""
		return
	endif

	if self.isReplCommand(cmd)
		call self.doReplCommand(cmd)
		return
	endif

	let result = vimclojure#ExecuteNailWithInput("CheckSyntax", cmd,
				\ "-n", b:vimclojure_namespace)
	if result == "false"
		execute "normal! GA\<CR>x"
		normal! ==x
		startinsert!
	else
		let result = vimclojure#ExecuteNailWithInput("Repl", cmd,
					\ "-r", "-i", self._id)
		call self.showText(result)

		let self._historyDepth = 0
		let self._history = [cmd] + self._history

		let namespace = vimclojure#ExecuteNailWithInput("Repl",
					\ "(clojure.core/ns-name clojure.core/*ns*)",
					\ "-r", "-I", "-i", self._id)
		let b:vimclojure_namespace = namespace
		let self._prompt = namespace . "=>"

		call self.showPrompt()
	endif
endfunction

function! vimclojure#Repl.upHistory() dict
	let histLen = len(self._history)
	let histDepth = self._historyDepth

	if histLen > 0 && histLen > histDepth
		let cmd = self._history[histDepth]
		let self._historyDepth = histDepth + 1

		call self.deleteLast()

		call self.showText(self._prompt . " " . cmd)
	endif

	normal! G$
endfunction

function! vimclojure#Repl.downHistory() dict
	let histLen = len(self._history)
	let histDepth = self._historyDepth

	if histDepth > 0 && histLen > 0
		let self._historyDepth = histDepth - 1
		let cmd = self._history[self._historyDepth]

		call self.deleteLast()

		call self.showText(self._prompt . " " . cmd)
	elseif histDepth == 0
		call self.deleteLast()
		call self.showText(self._prompt . " ")
	endif

	normal! G$
endfunction

function! vimclojure#Repl.deleteLast() dict
	normal! G

	while getline("$") !~ self._prompt
		normal! dd
	endwhile

	normal! dd
endfunction

" Highlighting
function! vimclojure#ColorNamespace(highlights)
	for [category, words] in items(a:highlights)
		if words != []
			execute "syntax keyword clojure" . category . " " . join(words, " ")
		endif
	endfor
endfunction

" Omni Completion
function! vimclojure#OmniCompletion(findstart, base)
	if a:findstart == 1
		let line = getline(".")
		let start = col(".") - 1

		while start > 0 && line[start - 1] =~ '\w\|-\|\.\|+\|*\|/'
			let start -= 1
		endwhile

		return start
	else
		let slash = stridx(a:base, '/')
		if slash > -1
			let prefix = strpart(a:base, 0, slash)
			let base = strpart(a:base, slash + 1)
		else
			let prefix = ""
			let base = a:base
		endif

		let completions = vimclojure#ExecuteNail("Complete",
					\ "-n", b:vimclojure_namespace,
					\ "-p", prefix, "-b", base)
		execute "let result = " . completions
		return result
	endif
endfunction

function! vimclojure#InitBuffer()
	if exists("g:clj_want_gorilla") && g:clj_want_gorilla == 1
		if !exists("b:vimclojure_namespace")
			" Get the namespace of the buffer.
			if &previewwindow
				let b:vimclojure_namespace = "user"
			else
				try
					let content = getbufline(bufnr("%"), 1, line("$"))
					let b:vimclojure_namespace =
								\ vimclojure#ExecuteNailWithInput(
								\   "NamespaceOfFile", content)
				catch /.*/
					echoerr "Could not determine the Namespace of the file. This might have different reasons. Please check, that the ng server is running with the correct classpath and that the file does not contain syntax errors. The interactive features will not be enabled, ie. the keybindings will not be mapped. Reason: " . v:exception
				endtry
			endif
		endif
	endif
endfunction

function! vimclojure#AddToLispWords(word)
	execute "setlocal lw+=" . a:word
endfunction

" Epilog
let &cpo = s:save_cpo
