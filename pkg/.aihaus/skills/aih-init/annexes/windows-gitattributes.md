# Windows Gitattributes Prompt

If `uname -s` contains `MINGW`, `MSYS`, or `CYGWIN` and no `.gitattributes`
exists at the repository root, ask:

> Windows detected, no .gitattributes. Git prints 'LF will be replaced by CRLF'
> warnings during milestone execution. Create a minimal .gitattributes to
> suppress? [y/N]

If yes, write:

```text
* text=auto eol=lf
*.sh text eol=lf
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.svg binary
*.webp binary
*.ico binary
*.pdf binary
*.woff binary
*.woff2 binary
```

Report created; otherwise skip silently.
