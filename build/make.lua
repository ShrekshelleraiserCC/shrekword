shell.run(("build sprint.lua build/sprint.lua -mini -version=%s"):format(os.date("%D")))
shell.run(("build sword.lua build/sword.lua -mini -version=%s"):format(os.date("%D")))
shell.run(("build sview.lua build/sview.lua -mini -version=%s"):format(os.date("%D")))
