" test execute()

import './util/vim9.vim' as v9

func NestedEval()
  let nested = execute('echo "nested\nlines"')
  echo 'got: "' . nested . '"'
endfunc

func NestedRedir()
  redir => var
  echo 'broken'
  redir END
endfunc

func Test_execute_string()
  call assert_equal("\nnocompatible", execute('set compatible?'))
  call assert_equal("\nsomething\nnice", execute('echo "something\nnice"'))
  call assert_equal("noendofline", execute('echon "noendofline"'))
  call assert_equal("", execute(123))

  call assert_equal("\ngot: \"\nnested\nlines\"", execute('call NestedEval()'))
  redir => redired
  echo 'this'
  let evaled = execute('echo "that"')
  echo 'theend'
  redir END
  call assert_equal("\nthis\ntheend", redired)
  call assert_equal("\nthat", evaled)

  call assert_fails('call execute("doesnotexist")', 'E492:')
  call assert_fails('call execute("call NestedRedir()")', 'E930:')

  call assert_equal("\nsomething", execute('echo "something"', ''))
  call assert_equal("\nsomething", execute('echo "something"', 'silent'))
  call assert_equal("\nsomething", execute('echo "something"', 'silent!'))
  call assert_equal("", execute('burp', 'silent!'))
  call assert_fails('call execute(3.4)', 'E492:')
  call assert_equal("\nx", execute("echo \"x\"", 3.4))
  call v9.CheckDefExecAndScriptFailure(['execute("echo \"x\"", 3.4)'], ['E1013: Argument 2: type mismatch, expected string but got float', 'E1174:'])
endfunc

func Test_execute_list()
  call assert_equal("\nsomething\nnice", execute(['echo "something"', 'echo "nice"']))
  let l = ['for n in range(0, 3)',
	\  'echo n',
	\  'endfor']
  call assert_equal("\n0\n1\n2\n3", execute(l))

  call assert_equal("", execute([]))
endfunc

func Test_execute_does_not_change_col()
  echo ''
  echon 'abcd'
  let x = execute('silent echo 234343')
  echon 'xyz'
  let text = ''
  for col in range(1, 7)
    let text .= nr2char(screenchar(&lines, col))
  endfor
  call assert_equal('abcdxyz', text)
endfunc

func Test_execute_not_silent()
  echo ''
  echon 'abcd'
  let x = execute('echon 234', '')
  echo 'xyz'
  let text1 = ''
  for col in range(1, 8)
    let text1 .= nr2char(screenchar(&lines - 1, col))
  endfor
  call assert_equal('abcd234 ', text1)
  let text2 = ''
  for col in range(1, 4)
    let text2 .= nr2char(screenchar(&lines, col))
  endfor
  call assert_equal('xyz ', text2)
endfunc

func Test_win_execute()
  let thiswin = win_getid()
  new
  let otherwin = win_getid()
  call setline(1, 'the new window')
  call win_gotoid(thiswin)
  let line = win_execute(otherwin, 'echo getline(1)')
  call assert_match('the new window', line)
  let line = win_execute(134343, 'echo getline(1)')
  call assert_equal('', line)

  if has('popupwin')
    let popupwin = popup_create('the popup win', {'line': 2, 'col': 3})
    redraw
    let line = 'echo getline(1)'->win_execute(popupwin)
    call assert_match('the popup win', line)

    call popup_close(popupwin)
  endif

  call win_gotoid(otherwin)
  bwipe!

  " check :lcd in another window does not change directory
  let curid = win_getid()
  let curdir = getcwd()
  split Xother
  lcd ..
  " Use :pwd to get the actual current directory
  let otherdir = execute('pwd')
  call win_execute(curid, 'lcd testdir')
  call assert_equal(otherdir, execute('pwd'))
  bwipe!
  execute 'cd ' .. curdir
endfunc

func Test_win_execute_update_ruler()
  CheckFeature quickfix

  enew
  call setline(1, range(500))
  20
  split
  let winid = win_getid()
  set ruler
  wincmd w
  let height = winheight(winid)
  redraw
  call assert_match('20,1', Screenline(height + 1))
  let line = win_execute(winid, 'call cursor(100, 1)')
  redraw
  call assert_match('100,1', Screenline(height + 1))

  bwipe!
endfunc

func Test_win_execute_other_tab()
  let thiswin = win_getid()
  tabnew
  call win_execute(thiswin, 'let xyz = 1')
  call assert_equal(1, xyz)
  tabclose
  unlet xyz
endfunc

func Test_win_execute_visual_redraw()
  call setline(1, ['a', 'b', 'c'])
  new
  wincmd p
  " start Visual in current window, redraw in other window with fewer lines
  call feedkeys("G\<C-V>", 'txn')
  call win_execute(winnr('#')->win_getid(), 'redraw')
  call feedkeys("\<Esc>", 'txn')
  bwipe!
  bwipe!

  enew
  new
  call setline(1, ['a', 'b', 'c'])
  let winid = win_getid()
  wincmd p
  " start Visual in current window, extend it in other window with more lines
  call feedkeys("\<C-V>", 'txn')
  call win_execute(winid, 'call feedkeys("G\<C-V>", ''txn'')')
  redraw

  bwipe!
  bwipe!
endfunc

func Test_win_execute_on_startup()
  CheckRunVimInTerminal

  let lines =<< trim END
      vim9script
      [repeat('x', &columns)]->writefile('Xfile1')
      silent tabedit Xfile2
      var id = win_getid()
      silent tabedit Xfile3
      autocmd VimEnter * win_execute(id, 'close')
  END
  call writefile(lines, 'XwinExecute', 'D')
  let buf = RunVimInTerminal('-p Xfile1 -Nu XwinExecute', {})

  " this was crashing on exit with EXITFREE defined
  call StopVimInTerminal(buf)

  call delete('Xfile1')
endfunc

func Test_execute_func_with_null()
  call assert_equal("", execute(test_null_string()))
  call assert_equal("", execute(test_null_list()))
  call assert_fails('call execute(test_null_dict())', 'E731:')
  call assert_fails('call execute(test_null_blob())', 'E976:')
  call assert_fails('call execute(test_null_partial())','E729:')
  if has('job')
    call assert_fails('call execute(test_null_job())', 'E908:')
    call assert_fails('call execute(test_null_channel())', 'E908:')
  endif
endfunc

func Test_win_execute_tabpagewinnr()
  belowright split
  tab split
  belowright split
  call assert_equal(2, tabpagewinnr(1))

  tabprevious
  wincmd p
  call assert_equal(1, tabpagenr())
  call assert_equal(1, tabpagewinnr(1))
  call assert_equal(2, tabpagewinnr(2))

  call win_execute(win_getid(1, 2),
        \      'call assert_equal(2, tabpagenr())'
        \ .. '| call assert_equal(1, tabpagewinnr(1))'
        \ .. '| call assert_equal(1, tabpagewinnr(2))')

  call assert_equal(1, tabpagenr())
  call assert_equal(1, tabpagewinnr(1))
  call assert_equal(2, tabpagewinnr(2))

  %bwipe!
endfunc

" vim: shiftwidth=2 sts=2 expandtab
